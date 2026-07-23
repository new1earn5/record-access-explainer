@IsTest
private class RAA_UserPopulationBuilderTest {
    @TestSetup
    static void setup() {
        User active = RAA_TestDataFactory.createUser('Pop', 'Active');
        User inactive = RAA_TestDataFactory.createUser('Pop', 'Inactive');
        inactive.IsActive = false;
        update inactive;
    }

    @IsTest
    static void defaultPopulationExcludesInactiveUsers() {
        User inactive = [SELECT Id FROM User WHERE LastName = 'Inactive' LIMIT 1];

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();

        Test.startTest();
        Set<Id> population = new RAA_UserPopulationBuilder().buildPopulation(filter, 0);
        Test.stopTest();

        System.assert(!population.contains(inactive.Id), 'Inactive users are excluded by default.');
    }

    @IsTest
    static void includeInactiveUsersAddsThemBack() {
        User inactive = [SELECT Id FROM User WHERE LastName = 'Inactive' LIMIT 1];

        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
        filter.includeInactiveUsers = true;

        Set<Id> population = new RAA_UserPopulationBuilder().buildPopulation(filter, 0);

        System.assert(
            population.contains(inactive.Id),
            'Setting includeInactiveUsers should add inactive users back into scope.'
        );
    }

    @IsTest
    static void throwsWhenPopulationExceedsConfiguredMaximum() {
        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
        filter.includeInactiveUsers = true;

        try {
            new RAA_UserPopulationBuilder().buildPopulation(filter, 1);
            System.assert(false, 'Expected an exception when the population exceeds the configured maximum.');
        } catch (RAA_AppException e) {
            System.assert(
                e.getMessage().contains('exceeds the configured maximum'),
                'Message should explain the limit was exceeded.'
            );
        }
    }

    @IsTest
    static void zeroMaximumMeansUnlimited() {
        RAA_UserPopulationBuilder.PopulationFilter filter = new RAA_UserPopulationBuilder.PopulationFilter();
        filter.includeInactiveUsers = true;

        Set<Id> population = new RAA_UserPopulationBuilder().buildPopulation(filter, 0);

        System.assert(
            population.size() >= 1,
            'A maximum of zero should not throw and should return the full population.'
        );
    }
}
