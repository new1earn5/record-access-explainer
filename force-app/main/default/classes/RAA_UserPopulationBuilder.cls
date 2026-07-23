/**
 * Builds the candidate user population for a scan. Defaults to all active internal users;
 * every other population dimension (external/Experience Cloud users, inactive users, specific
 * profiles, user types, or permission set assignments) is opt-in and additive on top of that
 * default, exactly as specified for the package's default scan behavior.
 */
public without sharing class RAA_UserPopulationBuilder {

    public class PopulationFilter {
        public Boolean includeExternalUsers = false;
        public Boolean includeInactiveUsers = false;
        public List<String> profileNames = new List<String>();
        public List<String> userTypes = new List<String>();
        public List<String> permissionSetNames = new List<String>();
    }

    public Set<Id> buildPopulation(PopulationFilter filter, Integer maxUsersPerScan) {
        List<String> whereClauses = new List<String>();

        if (!filter.includeInactiveUsers) {
            whereClauses.add('IsActive = true');
        }

        List<String> userTypes = filter.userTypes;
        if (userTypes != null && !userTypes.isEmpty()) {
            whereClauses.add('UserType IN :userTypes');
        } else if (!filter.includeExternalUsers) {
            whereClauses.add('UserType = \'Standard\'');
        }

        List<String> profileNames = filter.profileNames;
        if (profileNames != null && !profileNames.isEmpty()) {
            whereClauses.add('Profile.Name IN :profileNames');
        }

        List<String> permissionSetNames = filter.permissionSetNames;
        if (permissionSetNames != null && !permissionSetNames.isEmpty()) {
            whereClauses.add('Id IN (SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSet.Name IN :permissionSetNames)');
        }

        Integer queryLimit = maxUsersPerScan != null && maxUsersPerScan > 0 ? maxUsersPerScan + 1 : 50000;

        String query = 'SELECT Id FROM User';
        if (!whereClauses.isEmpty()) {
            query += ' WHERE ' + String.join(whereClauses, ' AND ');
        }
        query += ' ORDER BY Id LIMIT :queryLimit';

        List<User> users = Database.query(query);

        if (maxUsersPerScan != null && maxUsersPerScan > 0 && users.size() > maxUsersPerScan) {
            throw new RAA_AppException('This scan would include more than ' + maxUsersPerScan
                    + ' users, which exceeds the configured maximum in RAA Settings. Narrow the filters and try again.');
        }

        Set<Id> populationIds = new Set<Id>();
        for (User u : users) {
            populationIds.add(u.Id);
        }
        return populationIds;
    }
}
