/**
 * Shared test data builders for Record Access Explainer unit tests. Centralizing this avoids
 * duplicating boilerplate (unique usernames, required fields, and so on) across test classes.
 */
@IsTest
public class RAA_TestDataFactory {

    public static Integer userCounter = 0;

    public static User createUser(String firstName, String lastName) {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        userCounter++;
        String uniqueName = 'raa.test.' + userCounter + '.' + Crypto.getRandomInteger();
        User u = new User(
                FirstName = firstName,
                LastName = lastName,
                Alias = ('raa' + userCounter).left(8),
                Email = uniqueName + '@example.com',
                Username = uniqueName + '@example.com.raatest',
                ProfileId = standardProfile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                IsActive = true
        );
        insert u;
        return u;
    }

    public static RAA_Analysis__c createAnalysis(Id recordId, String objectApiName) {
        RAA_Analysis__c analysis = new RAA_Analysis__c(
                RAA_Record_Id__c = recordId,
                RAA_Object_API_Name__c = objectApiName,
                RAA_Record_Display_Name__c = 'Test Record',
                RAA_Status__c = 'Queued',
                RAA_Requested_By__c = UserInfo.getUserId(),
                RAA_Requested_At__c = System.now(),
                RAA_Include_External_Users__c = false,
                RAA_Include_Inactive_Users__c = false,
                RAA_Total_Users__c = 0,
                RAA_Processed_Users__c = 0,
                RAA_Users_With_Access__c = 0,
                RAA_Is_Complete__c = false
        );
        insert analysis;
        return analysis;
    }

    public static RAA_EffectiveAccessResult fullAccess(Id userId) {
        return new RAA_EffectiveAccessResult(userId, true, true, true, true, true, 'All');
    }

    public static RAA_EffectiveAccessResult readOnlyAccess(Id userId) {
        return new RAA_EffectiveAccessResult(userId, true, false, false, false, false, 'Read');
    }

    public static RAA_EffectiveAccessResult editAccess(Id userId) {
        return new RAA_EffectiveAccessResult(userId, true, true, false, false, false, 'Edit');
    }

    public static RAA_EffectiveAccessResult noAccess(Id userId) {
        return new RAA_EffectiveAccessResult(userId, false, false, false, false, false, 'None');
    }

    public static RAA_AccessReasonDTO buildReason(String category, String confidence) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = category;
        reason.accessLevel = 'Read';
        reason.confidence = confidence;
        reason.isDirect = true;
        reason.sourceName = 'Test Source';
        reason.sourceId = null;
        reason.sourceObject = 'Test';
        reason.principalId = null;
        reason.principalType = 'User';
        reason.rowCause = null;
        reason.grantPath = category + ' -> User';
        reason.explanation = 'Test explanation.';
        reason.evidence = 'Test evidence.';
        return reason;
    }
}
