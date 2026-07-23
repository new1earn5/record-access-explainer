/**
 * Dynamically locates the sharing table (Share object) for an arbitrary standard or custom
 * object using only Schema describe information - never a hardcoded object list. Handles the
 * standard-object convention (Account -> AccountShare, using "<Object>AccessLevel" as the
 * primary access field) and the custom-object convention (Custom__c -> Custom__Share, using
 * the generic "AccessLevel" field), and gracefully reports when no share object exists.
 */
public without sharing class RAA_ShareObjectResolver {

    public class ShareObjectInfo {
        public String shareObjectApiName;
        public String parentField;
        public String userOrGroupField;
        public String accessLevelField;
        public String rowCauseField;
        public List<String> secondaryAccessLevelFields = new List<String>();
    }

    public ShareObjectInfo resolve(Schema.DescribeSObjectResult objectDescribe) {
        String objectName = objectDescribe.getName();
        String candidateName = objectName.endsWithIgnoreCase('__c')
                ? objectName.substring(0, objectName.length() - 3) + '__Share'
                : objectName + 'Share';

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(candidateName)) {
            return null;
        }

        Schema.DescribeSObjectResult shareDescribe = globalDescribe.get(candidateName).getDescribe();
        if (!shareDescribe.isAccessible() && !shareDescribe.isQueryable()) {
            return null;
        }

        Map<String, Schema.SObjectField> shareFields = shareDescribe.fields.getMap();
        if (!shareFields.containsKey('UserOrGroupId') || !shareFields.containsKey('RowCause')) {
            return null;
        }

        ShareObjectInfo info = new ShareObjectInfo();
        info.shareObjectApiName = shareDescribe.getName();
        info.userOrGroupField = 'UserOrGroupId';
        info.rowCauseField = 'RowCause';
        info.parentField = findParentField(shareFields, objectDescribe.getSObjectType());
        if (info.parentField == null) {
            return null;
        }

        List<String> accessLevelFields = new List<String>();
        for (String fieldName : shareFields.keySet()) {
            if (fieldName.endsWithIgnoreCase('AccessLevel')) {
                accessLevelFields.add(shareFields.get(fieldName).getDescribe().getName());
            }
        }

        if (shareFields.containsKey('AccessLevel')) {
            info.accessLevelField = 'AccessLevel';
        } else {
            String preferred = objectName + 'AccessLevel';
            if (shareFields.containsKey(preferred)) {
                info.accessLevelField = shareFields.get(preferred).getDescribe().getName();
            } else if (!accessLevelFields.isEmpty()) {
                info.accessLevelField = accessLevelFields[0];
            }
        }

        for (String fieldName : accessLevelFields) {
            if (info.accessLevelField == null || !fieldName.equalsIgnoreCase(info.accessLevelField)) {
                info.secondaryAccessLevelFields.add(fieldName);
            }
        }

        if (info.accessLevelField == null) {
            return null;
        }

        return info;
    }

    private String findParentField(Map<String, Schema.SObjectField> shareFields, Schema.SObjectType targetType) {
        if (shareFields.containsKey('ParentId')) {
            Schema.DescribeFieldResult parentDescribe = shareFields.get('ParentId').getDescribe();
            if (parentDescribe.getReferenceTo().contains(targetType)) {
                return 'ParentId';
            }
        }
        for (String fieldName : shareFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = shareFields.get(fieldName).getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.REFERENCE) {
                continue;
            }
            if (fieldName.equalsIgnoreCase('UserOrGroupId')) {
                continue;
            }
            if (fieldDescribe.getReferenceTo().contains(targetType)) {
                return fieldDescribe.getName();
            }
        }
        return null;
    }
}
