/**
 * Aura-enabled input payload used to start a new analysis from the LWC.
 * All values are validated server-side; nothing here is trusted as-is.
 */
public class RAA_AnalysisRequestDTO {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public Boolean includeExternalUsers;
    @AuraEnabled
    public Boolean includeInactiveUsers;
    @AuraEnabled
    public List<String> profileNames;
    @AuraEnabled
    public List<String> userTypes;
    @AuraEnabled
    public List<String> permissionSetNames;
    @AuraEnabled
    public Boolean confirmDuplicateScan;
}
