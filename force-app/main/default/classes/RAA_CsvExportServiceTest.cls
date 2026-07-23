@IsTest
private class RAA_CsvExportServiceTest {

    private static RAA_AccessResultDTO buildResult(String name, String reasonSummary) {
        RAA_AccessResultDTO result = new RAA_AccessResultDTO();
        result.userFullName = name;
        result.username = name + '@example.com';
        result.isActive = true;
        result.userType = 'Standard';
        result.profileName = 'Standard User';
        result.maxAccessLevel = 'Edit';
        result.hasReadAccess = true;
        result.hasEditAccess = true;
        result.hasDeleteAccess = false;
        result.hasTransferAccess = false;
        result.hasAllAccess = false;
        result.reasonSummary = reasonSummary;
        result.overallConfidence = 'High';
        result.reasons = new List<RAA_AccessReasonDTO>();
        return result;
    }

    @IsTest
    static void escapesCommasQuotesAndLineBreaks() {
        RAA_AccessResultDTO result = buildResult('Smith, John "The Boss"', 'Ownership; Direct Share' + '\n' + 'Second line');

        Test.startTest();
        String csv = new RAA_CsvExportService().buildResultsCsv(new List<RAA_AccessResultDTO>{ result });
        Test.stopTest();

        System.assert(csv.contains('"Smith, John ""The Boss"""'), 'Commas and quotes must be escaped per RFC 4180.');
        System.assert(csv.contains('"Ownership; Direct Share'), 'A field containing a line break must be quoted.');
    }

    @IsTest
    static void includesHeaderRowEvenForEmptyResults() {
        String csv = new RAA_CsvExportService().buildResultsCsv(new List<RAA_AccessResultDTO>());
        System.assert(csv.startsWith('User,Username,Active'), 'Header row should always be present.');
        System.assertEquals(1, csv.split('\n').size(), 'An empty result set should only produce the header line.');
    }

    @IsTest
    static void reasonsCsvIncludesOneRowPerReason() {
        RAA_AccessResultDTO result = buildResult('Jane Doe', 'Ownership');
        RAA_AccessReasonDTO reasonOne = RAA_TestDataFactory.buildReason('Ownership', 'High');
        RAA_AccessReasonDTO reasonTwo = RAA_TestDataFactory.buildReason('Permission', 'Medium');
        result.reasons.add(reasonOne);
        result.reasons.add(reasonTwo);

        String csv = new RAA_CsvExportService().buildReasonsCsv(new List<RAA_AccessResultDTO>{ result });

        List<String> lines = csv.split('\n');
        System.assertEquals(3, lines.size(), 'Header plus one line per reason.');
    }

    @IsTest
    static void handlesNullResultListsGracefully() {
        String resultsCsv = new RAA_CsvExportService().buildResultsCsv(null);
        String reasonsCsv = new RAA_CsvExportService().buildReasonsCsv(null);
        System.assert(resultsCsv.length() > 0, 'A null list should still produce a header row.');
        System.assert(reasonsCsv.length() > 0, 'A null list should still produce a header row.');
    }
}
