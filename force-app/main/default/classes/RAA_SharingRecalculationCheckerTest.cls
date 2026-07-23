@IsTest
private class RAA_SharingRecalculationCheckerTest {

    @IsTest
    static void returnsFalseWhenNoRecalculationJobIsRunning() {
        Test.startTest();
        Boolean result = new RAA_SharingRecalculationChecker().isRecalculationInProgress();
        Test.stopTest();

        // A fresh test transaction never has a real SharingRecalculation job queued, so this
        // exercises the "nothing in progress" path deterministically.
        System.assertEquals(false, result);
    }
}
