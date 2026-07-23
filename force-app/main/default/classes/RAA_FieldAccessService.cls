/**
 * Computes field-level security for one user against one object, for every field. Field-level
 * security merges permissively across every assigned permission set (including the profile-owned
 * one): a field is readable/editable if *any* assigned permission set grants it, not only if all
 * of them do. Fields that are not permission-controlled at all (DescribeFieldResult.isPermissionable()
 * is false - for example, Id) are always reported as accessible, matching actual platform behavior.
 *
 * This is deliberately not persisted anywhere: a record could have dozens of fields, and
 * multiplying that by every user in a scan would make the data model unmanageable. It is instead
 * computed live, on demand, for a single user at a time.
 */
public without sharing class RAA_FieldAccessService {
    private final RAA_PermissionSetLookup permissionSetLookup;

    public RAA_FieldAccessService() {
        this(new RAA_PermissionSetLookup());
    }

    public RAA_FieldAccessService(RAA_PermissionSetLookup permissionSetLookup) {
        this.permissionSetLookup = permissionSetLookup;
    }

    public List<RAA_FieldAccessDTO> getFieldAccess(Id userId, String objectApiName) {
        List<RAA_FieldAccessDTO> results = new List<RAA_FieldAccessDTO>();
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            throw new RAA_AppException('"' + objectApiName + '" is not a recognized object.');
        }

        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        List<PermissionSetAssignment> assignments = permissionSetLookup.getAssignments(new Set<Id>{ userId });
        Set<Id> permissionSetIds = permissionSetLookup.permissionSetIds(assignments);

        Set<String> readableFields = new Set<String>();
        Set<String> editableFields = new Set<String>();
        if (!permissionSetIds.isEmpty()) {
            for (FieldPermissions fp : [
                SELECT Field, PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId IN :permissionSetIds AND SobjectType = :objectApiName
            ]) {
                String fieldApiName = fp.Field.contains('.') ? fp.Field.substringAfter('.') : fp.Field;
                if (fp.PermissionsRead) {
                    readableFields.add(fieldApiName.toLowerCase());
                }
                if (fp.PermissionsEdit) {
                    editableFields.add(fieldApiName.toLowerCase());
                }
            }
        }

        List<String> fieldNames = new List<String>(fieldMap.keySet());
        fieldNames.sort();

        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            RAA_FieldAccessDTO dto = new RAA_FieldAccessDTO();
            dto.fieldApiName = fieldDescribe.getName();
            dto.fieldLabel = fieldDescribe.getLabel();
            if (!fieldDescribe.isPermissionable()) {
                dto.readable = true;
                dto.editable = true;
            } else {
                dto.readable = readableFields.contains(fieldName.toLowerCase());
                dto.editable = editableFields.contains(fieldName.toLowerCase());
            }
            results.add(dto);
        }

        return results;
    }
}
