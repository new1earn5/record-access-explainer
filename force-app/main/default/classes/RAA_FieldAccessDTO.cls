/**
 * Aura-enabled field-level security summary for a single field, for a single user, on the
 * analyzed object.
 */
public class RAA_FieldAccessDTO {
    @AuraEnabled public String fieldApiName;
    @AuraEnabled public String fieldLabel;
    @AuraEnabled public Boolean readable;
    @AuraEnabled public Boolean editable;
}
