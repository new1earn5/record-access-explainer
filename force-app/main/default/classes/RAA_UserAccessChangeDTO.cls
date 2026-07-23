/**
 * Aura-enabled description of how one user's access differs between two analyses of the same
 * record.
 */
public class RAA_UserAccessChangeDTO {
    @AuraEnabled
    public String userId;
    @AuraEnabled
    public String userFullName;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public String changeType; // Added, Removed, Changed
    @AuraEnabled
    public String previousMaxAccessLevel;
    @AuraEnabled
    public String currentMaxAccessLevel;
    @AuraEnabled
    public String previousReasonSummary;
    @AuraEnabled
    public String currentReasonSummary;
}
