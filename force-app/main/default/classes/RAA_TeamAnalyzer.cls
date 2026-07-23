/**
 * Detects access granted through Account Team, Opportunity Team, or Case Team membership.
 * AccountTeamMember, OpportunityTeamMember, CaseTeamMember, and CaseTeamRole are referenced only
 * through fully dynamic SOQL (never a compile-time sObject type): Account Teams, Opportunity
 * Teams, and Case Teams are opt-in features that an org may never have enabled, and a static
 * reference would break deployment entirely in orgs where the corresponding objects are absent.
 * When the relevant object or feature is unavailable, this analyzer silently contributes nothing
 * for that record rather than raising a warning, since the feature simply may not be in use.
 */
public without sharing class RAA_TeamAnalyzer implements RAA_IReasonAnalyzer {

    public String getAnalyzerName() {
        return 'Teams';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        try {
            if (context.objectApiName == 'Account' && globalDescribe.containsKey('AccountTeamMember')) {
                analyzeTeam(context, userIds, results, 'AccountTeamMember', 'AccountId', 'UserId',
                        'TeamMemberRole', 'AccountAccessLevel', 'Account Team');
            } else if (context.objectApiName == 'Opportunity' && globalDescribe.containsKey('OpportunityTeamMember')) {
                analyzeTeam(context, userIds, results, 'OpportunityTeamMember', 'OpportunityId', 'UserId',
                        'TeamMemberRole', 'OpportunityAccessLevel', 'Opportunity Team');
            } else if (context.objectApiName == 'Case' && globalDescribe.containsKey('CaseTeamMember')) {
                analyzeCaseTeam(context, userIds, results);
            }
        } catch (System.QueryException e) {
            context.warnings.add('Team analysis could not be completed for ' + context.objectApiName
                    + ': the relevant team feature may not be enabled in this org.');
        }

        return results;
    }

    private void analyzeTeam(RAA_AnalysisContext context, Set<Id> userIds, Map<Id, List<RAA_AccessReasonDTO>> results,
            String teamObject, String parentField, String userField, String roleField, String accessLevelField, String teamLabel) {
        Id recordId = context.recordId;
        String query = 'SELECT ' + userField + ', ' + roleField + ', ' + accessLevelField
                + ' FROM ' + teamObject
                + ' WHERE ' + parentField + ' = :recordId AND ' + userField + ' IN :userIds';
        for (SObject member : Database.query(query)) {
            Id userId = (Id) member.get(userField);
            String role = (String) member.get(roleField);
            String accessLevel = (String) member.get(accessLevelField);
            addReason(results, userId, buildReason(context, teamLabel, accessLevel, role,
                    teamLabel + ' member with role "' + role + '".'));
        }
    }

    private void analyzeCaseTeam(RAA_AnalysisContext context, Set<Id> userIds, Map<Id, List<RAA_AccessReasonDTO>> results) {
        Map<Id, String> roleNamesById = new Map<Id, String>();
        if (Schema.getGlobalDescribe().containsKey('CaseTeamRole')) {
            for (SObject role : Database.query('SELECT Id, Name FROM CaseTeamRole')) {
                roleNamesById.put((Id) role.get('Id'), (String) role.get('Name'));
            }
        }

        Id recordId = context.recordId;
        for (SObject member : Database.query(
                'SELECT MemberId, TeamRoleId FROM CaseTeamMember WHERE ParentId = :recordId AND MemberId IN :userIds')) {
            Id userId = (Id) member.get('MemberId');
            Id roleId = (Id) member.get('TeamRoleId');
            String roleName = roleNamesById.containsKey(roleId) ? roleNamesById.get(roleId) : 'Unknown';
            addReason(results, userId, buildReason(context, 'Case Team', null, roleName,
                    'Case team member with role "' + roleName + '".'));
        }
    }

    private RAA_AccessReasonDTO buildReason(RAA_AnalysisContext context, String teamType, String accessLevel,
            String role, String explanation) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = 'Team';
        reason.accessLevel = accessLevel;
        reason.confidence = 'High';
        reason.isDirect = true;
        reason.sourceName = teamType;
        reason.sourceId = null;
        reason.sourceObject = teamType.replace(' ', '') + 'Member';
        reason.principalId = null;
        reason.principalType = 'User';
        reason.rowCause = 'Team';
        reason.grantPath = context.prefixedPath(teamType + ' (' + role + ') -> User');
        reason.explanation = explanation;
        reason.evidence = teamType + ' role: ' + role + '; AccessLevel: ' + accessLevel;
        return reason;
    }

    private void addReason(Map<Id, List<RAA_AccessReasonDTO>> results, Id userId, RAA_AccessReasonDTO reason) {
        List<RAA_AccessReasonDTO> reasonList = results.get(userId);
        if (reasonList == null) {
            reasonList = new List<RAA_AccessReasonDTO>();
            results.put(userId, reasonList);
        }
        reasonList.add(reason);
    }
}
