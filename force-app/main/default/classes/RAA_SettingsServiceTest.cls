@IsTest
private class RAA_SettingsServiceTest {

    @IsTest
    static void loadsPackagedDefaultRecord() {
        Test.startTest();
        RAA_SettingsService settings = new RAA_SettingsService();
        Test.stopTest();

        System.assertEquals(20, settings.defaultBatchScope, 'Packaged default batch scope should be 20.');
        System.assertEquals(6, settings.maxGroupDepth, 'Packaged default max group depth should be 6.');
        System.assertEquals(5, settings.maxParentDepth, 'Packaged default max parent depth should be 5.');
        System.assertEquals(90, settings.retentionDays, 'Packaged default retention should be 90 days.');
        System.assertEquals(false, settings.defaultIncludeExternal, 'External users should be opt-in by default.');
        System.assertEquals(false, settings.defaultIncludeInactive, 'Inactive users should be opt-in by default.');
        System.assertEquals(0, settings.maxUsersPerScan, 'Packaged default max users per scan should be unlimited (0).');
        System.assertEquals(200, settings.maxRecordsPerBulkRun, 'Packaged default max records per bulk run should be 200.');
        System.assertEquals(200, settings.maxRecordsPerUserScan, 'Packaged default max records per user scan should be 200.');
    }
}
