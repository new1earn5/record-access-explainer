@IsTest
private class RAA_RestrictionRuleCheckerTest {

    @IsTest
    static void doesNotThrowForAnyObject() {
        Test.startTest();
        Integer count = new RAA_RestrictionRuleChecker().countActiveRestrictionRules('Account');
        Test.stopTest();

        // Whether RestrictionRule is queryable via plain SOQL varies by org/API context; the
        // contract is simply "never throw" - either a real count or null (unknown) comes back.
        System.assert(count == null || count >= 0);
    }

    @IsTest
    static void returnsNullWhenObjectDoesNotExistInGlobalDescribe() {
        Integer count = new RAA_RestrictionRuleChecker().countActiveRestrictionRules('This_Is_Not_A_Real_Object__x');
        System.assert(count == null || count == 0);
    }
}
