/**
 * Reusable, bulk-query BFS resolver over the Group / GroupMember membership graph.
 * Supports nested Regular public groups, Queues, and direct Role-type group membership
 * (Salesforce materializes GroupMember rows for those types). "Roles and Subordinates",
 * "Territory", and "Territory and Subordinates" principal types are not backed by GroupMember
 * rows at all - those are resolved by RAA_RoleHierarchyAnalyzer and RAA_TerritoryAnalyzer
 * respectively using role/territory hierarchy data instead, so this resolver simply stops (and
 * reports) when it reaches one of those node types rather than guessing.
 *
 * One SOQL pair (Group describe + GroupMember) is issued per BFS depth level, never per group
 * and never per user, so cost scales with graph depth (bounded by RAA_Settings__mdt) rather
 * than with population size.
 */
public without sharing class RAA_GroupGraphResolver {

    public static final Set<String> UNRESOLVABLE_TYPES = new Set<String>{
            'RoleAndSubordinates', 'RoleAndSubordinatesInternal', 'Territory', 'TerritoryAndSubordinates'
    };

    public Map<Id, Group> describeGroups(Set<Id> groupIds) {
        Map<Id, Group> result = new Map<Id, Group>();
        if (groupIds == null || groupIds.isEmpty()) {
            return result;
        }
        for (Group g : [SELECT Id, Name, DeveloperName, Type, RelatedId FROM Group WHERE Id IN :groupIds]) {
            result.put(g.Id, g);
        }
        return result;
    }

    /**
     * Resolves membership paths from each root principal (typically a Group referenced by a
     * share row) down to any of the target users, breadth-first, up to maxDepth levels.
     * Returns a map of userId -> one path per distinct root principal that can reach that user.
     */
    public Map<Id, List<RAA_GroupPathDTO>> resolvePaths(Set<Id> rootGroupIds, Set<Id> targetUserIds, Integer maxDepth) {
        Map<Id, List<RAA_GroupPathDTO>> resultsByUser = new Map<Id, List<RAA_GroupPathDTO>>();
        if (rootGroupIds == null || rootGroupIds.isEmpty() || targetUserIds == null || targetUserIds.isEmpty()) {
            return resultsByUser;
        }

        Map<Id, Group> rootInfo = describeGroups(rootGroupIds);

        for (Id rootId : rootGroupIds) {
            resolveFromSingleRoot(rootId, rootInfo.get(rootId), targetUserIds, maxDepth, resultsByUser);
        }
        return resultsByUser;
    }

    private void resolveFromSingleRoot(Id rootId, Group rootGroup, Set<Id> targetUserIds, Integer maxDepth,
            Map<Id, List<RAA_GroupPathDTO>> resultsByUser) {

        if (rootGroup == null) {
            return;
        }

        Set<Id> remainingTargets = new Set<Id>(targetUserIds);
        Set<Id> visitedGroupIds = new Set<Id>{ rootId };
        Map<Id, List<String>> pathLabelsByGroupId = new Map<Id, List<String>>{
                rootId => new List<String>{ describeLabel(rootGroup) }
        };

        Set<Id> currentLevel = new Set<Id>{ rootId };
        Integer depth = 0;

        while (!currentLevel.isEmpty() && depth < maxDepth && !remainingTargets.isEmpty()) {
            Set<Id> nextLevel = new Set<Id>();

            List<Id> orderedGroupIds = new List<Id>(currentLevel);
            orderedGroupIds.sort();

            List<GroupMember> members = [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :orderedGroupIds
                ORDER BY GroupId, UserOrGroupId
            ];

            // Describe every child group referenced by this level's members up front (one bulk
            // query), so labels are available when building each child's path below.
            Set<Id> childGroupIds = new Set<Id>();
            for (GroupMember gm : members) {
                if (gm.UserOrGroupId.getSObjectType() == Group.SObjectType) {
                    childGroupIds.add(gm.UserOrGroupId);
                }
            }
            Map<Id, Group> childGroupInfo = describeGroups(childGroupIds);

            for (GroupMember gm : members) {
                List<String> parentPath = pathLabelsByGroupId.get(gm.GroupId);
                if (parentPath == null) {
                    continue;
                }
                Schema.SObjectType memberType = gm.UserOrGroupId.getSObjectType();

                if (memberType == User.SObjectType) {
                    if (remainingTargets.contains(gm.UserOrGroupId)) {
                        List<RAA_GroupPathDTO> existing = resultsByUser.get(gm.UserOrGroupId);
                        if (existing == null) {
                            existing = new List<RAA_GroupPathDTO>();
                            resultsByUser.put(gm.UserOrGroupId, existing);
                        }
                        existing.add(new RAA_GroupPathDTO(rootId, rootGroup.Type, describeLabel(rootGroup), parentPath));
                    }
                } else if (memberType == Group.SObjectType) {
                    if (visitedGroupIds.contains(gm.UserOrGroupId)) {
                        continue; // cycle guard: already on a path from this root
                    }
                    visitedGroupIds.add(gm.UserOrGroupId);
                    nextLevel.add((Id) gm.UserOrGroupId);
                    List<String> childPath = new List<String>(parentPath);
                    Group childGroup = childGroupInfo.get((Id) gm.UserOrGroupId);
                    childPath.add(childGroup != null ? describeLabel(childGroup) : 'Group: ' + gm.UserOrGroupId);
                    pathLabelsByGroupId.put((Id) gm.UserOrGroupId, childPath);
                }
            }

            currentLevel = nextLevel;
            depth++;
        }
    }

    private String describeLabel(Group g) {
        if (g == null) {
            return 'Group';
        }
        if (g.Type == 'Queue') {
            return 'Queue: ' + g.Name;
        }
        if (g.Type == 'Role') {
            return 'Role Group: ' + g.Name;
        }
        if (UNRESOLVABLE_TYPES.contains(g.Type)) {
            return g.Type + ': ' + g.Name;
        }
        return 'Public Group: ' + g.Name;
    }
}
