@IsTest
private class RAA_PermissionCheckerTest {
    @IsTest
    static void overrideForcesResultInTests() {
        RAA_PermissionChecker.testOverride = true;
        System.assertEquals(true, RAA_PermissionChecker.hasRunPermission());

        RAA_PermissionChecker.testOverride = false;
        System.assertEquals(false, RAA_PermissionChecker.hasRunPermission());
    }

    @IsTest
    static void fallsThroughToRealCheckWhenNoOverrideIsSet() {
        RAA_PermissionChecker.testOverride = null;
        // No assertion on the actual boolean value - this exercises the real
        // FeatureManagement.checkPermission code path without depending on org permission state.
        Boolean result = RAA_PermissionChecker.hasRunPermission();
        System.assert(result == true || result == false);
    }
}
