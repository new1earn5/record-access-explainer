/**
 * One row of a standalone org-wide oversharing scan: a Profile or Permission Set that grants
 * broad object-level access to one object, together with how many active users currently hold
 * it. Unlike the rest of this package, nothing here is about a specific record - it complements
 * the per-record scan with a "where's my exposure, org-wide" starting point (in the spirit of
 * tools like NCC Group's Raccoon), built entirely from ObjectPermissions/PermissionSet/Profile
 * describes, not from any RAA_* custom object.
 */
public class RAA_OrgWideAccessDTO {
    @AuraEnabled
    public String principalName;
    @AuraEnabled
    public String principalType; // 'Profile' or 'Permission Set'
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public Boolean hasViewAllRecords;
    @AuraEnabled
    public Boolean hasModifyAllRecords;
    @AuraEnabled
    public Boolean hasFullObjectCrud;
    @AuraEnabled
    public Integer activeUserCount;
}
