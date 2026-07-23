/**
 * Aura-enabled snapshot of the default scan settings, used to pre-fill the scan input form.
 */
public class RAA_SettingsDTO {
    @AuraEnabled public Boolean defaultIncludeExternalUsers;
    @AuraEnabled public Boolean defaultIncludeInactiveUsers;
    @AuraEnabled public Integer maxUsersPerScan;

    public RAA_SettingsDTO(RAA_SettingsService settings) {
        this.defaultIncludeExternalUsers = settings.defaultIncludeExternal;
        this.defaultIncludeInactiveUsers = settings.defaultIncludeInactive;
        this.maxUsersPerScan = settings.maxUsersPerScan;
    }
}
