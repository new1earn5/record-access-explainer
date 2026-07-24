/**
 * Detects access granted by system-wide or object-wide permissions: View All Data,
 * Modify All Data, and object-level View All Records / Modify All Records, sourced from a
 * user's profile-owned permission set, directly assigned permission sets, and permission sets
 * obtained through an assigned permission set group.
 *
 * Plain object CRUD (Read/Edit/Delete without a "view/modify all" bypass) is deliberately NOT
 * reported as a standalone access reason: object-level CRUD is only a prerequisite for record
 * access, never sufficient on its own to explain access to a Private record, and reporting it
 * as a reason would overstate what the permission actually proves.
 *
 * Muting permission set groups are a known Salesforce feature that can reduce a permission set
 * group's effective permissions below what its member permission sets grant. This was
 * investigated, but MutingPermissionSet does not expose a queryable field linking it back to a
 * specific PermissionSetGroup or PermissionSet in this API version, so there is no supported way
 * to detect which groups are affected via SOQL. Rather than emit a caveat that cannot be tied to
 * a specific result, muting is not represented here; permission-set-group-derived reasons should
 * be treated as the group's nominal (not necessarily muting-adjusted) effective permissions.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: part of the elevated scan pipeline (see
// README.md §1, "Batch Apex runs in system mode"), reached only through the with-sharing
// controller's permission and per-record visibility gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_PermissionAnalyzer implements RAA_IReasonAnalyzer {
    public String getAnalyzerName() {
        return 'Permissions';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }

        List<PermissionSetAssignment> assignments = [
            SELECT
                AssigneeId,
                PermissionSetId,
                PermissionSetGroupId,
                PermissionSet.Label,
                PermissionSet.IsOwnedByProfile,
                PermissionSet.Profile.Name,
                PermissionSet.PermissionsViewAllData,
                PermissionSet.PermissionsModifyAllData,
                PermissionSetGroup.MasterLabel
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :userIds
        ];
        if (assignments.isEmpty()) {
            return results;
        }

        Set<Id> permissionSetIds = new Set<Id>();
        for (PermissionSetAssignment psa : assignments) {
            permissionSetIds.add(psa.PermissionSetId);
        }

        Map<Id, ObjectPermissions> objectPermsBySetId = new Map<Id, ObjectPermissions>();
        for (ObjectPermissions op : [
            SELECT
                ParentId,
                PermissionsRead,
                PermissionsEdit,
                PermissionsDelete,
                PermissionsViewAllRecords,
                PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :permissionSetIds AND SobjectType = :context.objectApiName
        ]) {
            objectPermsBySetId.put(op.ParentId, op);
        }

        for (PermissionSetAssignment psa : assignments) {
            if (!userIds.contains(psa.AssigneeId)) {
                continue;
            }

            String sourceName;
            Boolean isDirect;
            if (psa.PermissionSetGroupId != null) {
                sourceName = 'permission set group: ' + psa.PermissionSetGroup.MasterLabel;
                isDirect = false;
            } else if (psa.PermissionSet.IsOwnedByProfile) {
                sourceName = 'profile: ' + psa.PermissionSet.Profile.Name;
                isDirect = true;
            } else {
                sourceName = 'permission set: ' + psa.PermissionSet.Label;
                isDirect = true;
            }

            if (psa.PermissionSet.PermissionsViewAllData) {
                addReason(
                    results,
                    psa.AssigneeId,
                    buildReason(
                        context,
                        'Permission',
                        'Full Access (organization-wide)',
                        'High',
                        isDirect,
                        sourceName,
                        psa.PermissionSetId,
                        'View All Data from ' + sourceName + '.',
                        'This permission bypasses record-level sharing entirely for all objects.'
                    )
                );
            }
            if (psa.PermissionSet.PermissionsModifyAllData) {
                addReason(
                    results,
                    psa.AssigneeId,
                    buildReason(
                        context,
                        'Permission',
                        'Full Access (organization-wide)',
                        'High',
                        isDirect,
                        sourceName,
                        psa.PermissionSetId,
                        'Modify All Data from ' + sourceName + '.',
                        'This permission bypasses record-level sharing entirely for all objects, including delete and transfer.'
                    )
                );
            }

            ObjectPermissions op = objectPermsBySetId.get(psa.PermissionSetId);
            if (op == null) {
                continue;
            }
            if (op.PermissionsViewAllRecords) {
                addReason(
                    results,
                    psa.AssigneeId,
                    buildReason(
                        context,
                        'Permission',
                        'Read (object-wide)',
                        'High',
                        isDirect,
                        sourceName,
                        psa.PermissionSetId,
                        'View All Records on ' + context.objectApiName + ' from ' + sourceName + '.',
                        'This permission bypasses record-level sharing for this object only.'
                    )
                );
            }
            if (op.PermissionsModifyAllRecords) {
                addReason(
                    results,
                    psa.AssigneeId,
                    buildReason(
                        context,
                        'Permission',
                        'Edit/Delete (object-wide)',
                        'High',
                        isDirect,
                        sourceName,
                        psa.PermissionSetId,
                        'Modify All Records on ' + context.objectApiName + ' from ' + sourceName + '.',
                        'This permission bypasses record-level sharing for this object only, including delete and transfer.'
                    )
                );
            }
        }

        return results;
    }

    private RAA_AccessReasonDTO buildReason(
        RAA_AnalysisContext context,
        String category,
        String accessLevel,
        String confidence,
        Boolean isDirect,
        String sourceName,
        Id sourceId,
        String explanation,
        String bypassNote
    ) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = category;
        reason.accessLevel = accessLevel;
        reason.confidence = confidence;
        reason.isDirect = isDirect;
        reason.sourceName = sourceName;
        reason.sourceId = sourceId;
        reason.sourceObject = 'PermissionSet';
        reason.principalId = sourceId;
        reason.principalType = 'PermissionSet';
        reason.rowCause = null;
        reason.grantPath = context.prefixedPath(sourceName + ' -> User');
        reason.explanation = explanation + ' ' + bypassNote;
        reason.evidence = 'PermissionSetId: ' + sourceId + '; Object: ' + context.objectApiName;
        return reason;
    }

    private void addReason(Map<Id, List<RAA_AccessReasonDTO>> results, Id userId, RAA_AccessReasonDTO reason) {
        List<RAA_AccessReasonDTO> reasonList = results.get(userId);
        if (reasonList == null) {
            reasonList = new List<RAA_AccessReasonDTO>();
            results.put(userId, reasonList);
        }
        reasonList.add(reason);
    }
}
