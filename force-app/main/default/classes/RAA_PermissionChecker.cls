/**
 * Thin wrapper around FeatureManagement.checkPermission for the RAA_Run_Record_Access_Analysis
 * custom permission. FeatureManagement.checkPermission reads from a session-level permission
 * cache that does not refresh within a single Apex test transaction, so a PermissionSetAssignment
 * inserted in a test (even in @TestSetup) is not reliably reflected by a later call in the same
 * test run - a well-documented Apex testing limitation, not a bug in this class. testOverride
 * lets test code force a deterministic result; it only has any effect while Test.isRunningTest()
 * is true, so it can never be used to bypass the real permission check outside of tests.
 */
public without sharing class RAA_PermissionChecker {
    private static final String RUN_PERMISSION = 'RAA_Run_Record_Access_Analysis';

    @TestVisible
    private static Boolean testOverride = null;

    public static Boolean hasRunPermission() {
        if (Test.isRunningTest() && testOverride != null) {
            return testOverride;
        }
        return FeatureManagement.checkPermission(RUN_PERMISSION);
    }
}
