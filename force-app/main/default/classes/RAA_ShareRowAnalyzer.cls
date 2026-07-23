/**
 * Classifies rows from the record's dynamically resolved Share object (context.shareRows,
 * bulk-loaded once per record by the aggregator) into Direct Share, Group Share, Sharing Rule,
 * and Implicit reasons. Team-caused share rows (RowCause = 'Team') are intentionally skipped
 * here and reported by RAA_TeamAnalyzer instead, which can attach the specific team role.
 * Group principal membership is resolved with a single batched RAA_GroupGraphResolver call
 * covering every group referenced by any share row, not one call per row.
 */
public without sharing class RAA_ShareRowAnalyzer implements RAA_IReasonAnalyzer {

    private final RAA_GroupGraphResolver groupResolver;

    public RAA_ShareRowAnalyzer() {
        this(new RAA_GroupGraphResolver());
    }

    public RAA_ShareRowAnalyzer(RAA_GroupGraphResolver groupResolver) {
        this.groupResolver = groupResolver;
    }

    public String getAnalyzerName() {
        return 'Share Rows';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (context.shareObjectApiName == null || context.shareRows == null || context.shareRows.isEmpty()) {
            return results;
        }

        Set<Id> groupPrincipalIds = new Set<Id>();
        for (SObject row : context.shareRows) {
            String rowCause = (String) row.get(context.shareRowCauseField);
            if (rowCause == 'Team') {
                continue;
            }
            Id principalId = (Id) row.get(context.shareUserOrGroupField);
            if (principalId != null && principalId.getSObjectType() == Group.SObjectType) {
                groupPrincipalIds.add(principalId);
            }
        }

        Map<Id, List<RAA_GroupPathDTO>> groupPaths = groupResolver.resolvePaths(groupPrincipalIds, userIds, context.maxGroupDepth);
        Map<Id, Group> groupInfo = groupResolver.describeGroups(groupPrincipalIds);

        for (SObject row : context.shareRows) {
            String rowCause = (String) row.get(context.shareRowCauseField);
            if (rowCause == 'Team') {
                continue;
            }
            Id principalId = (Id) row.get(context.shareUserOrGroupField);
            String accessLevel = (String) row.get(context.shareAccessLevelField);
            if (principalId == null) {
                continue;
            }

            if (principalId.getSObjectType() == User.SObjectType) {
                if (userIds.contains(principalId)) {
                    addReason(results, principalId, buildDirectUserReason(context, principalId, accessLevel, rowCause));
                }
                continue;
            }

            if (principalId.getSObjectType() != Group.SObjectType) {
                continue;
            }

            // groupPaths is keyed by userId, not by group; scan for any user paths rooted at this principal.
            for (Id userId : groupPaths.keySet()) {
                if (!userIds.contains(userId)) {
                    continue;
                }
                for (RAA_GroupPathDTO path : groupPaths.get(userId)) {
                    if (path.principalId != principalId) {
                        continue;
                    }
                    addReason(results, userId, buildGroupReason(context, path, accessLevel, rowCause, groupInfo.get(principalId)));
                }
            }
        }

        return results;
    }

    private RAA_AccessReasonDTO buildDirectUserReason(RAA_AnalysisContext context, Id userId, String accessLevel, String rowCause) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = 'Direct Share';
        reason.accessLevel = accessLevel;
        reason.confidence = 'High';
        reason.isDirect = true;
        reason.sourceName = context.shareObjectApiName;
        reason.sourceId = null;
        reason.sourceObject = context.shareObjectApiName;
        reason.principalId = userId;
        reason.principalType = 'User';
        reason.rowCause = rowCause;
        reason.grantPath = context.prefixedPath('Direct Share -> User');
        reason.explanation = rowCause == 'Manual'
                ? 'A manual share row grants this user direct access to the record.'
                : 'A share row (RowCause = "' + rowCause + '") grants this user direct access to the record.';
        reason.evidence = 'Share object: ' + context.shareObjectApiName + '; RowCause: ' + rowCause + '; AccessLevel: ' + accessLevel;
        return reason;
    }

    private RAA_AccessReasonDTO buildGroupReason(RAA_AnalysisContext context, RAA_GroupPathDTO path, String accessLevel,
            String rowCause, Group principalGroup) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        Boolean isRule = rowCause == 'Rule';
        Boolean isImplicit = rowCause == 'ImplicitChild' || rowCause == 'ImplicitParent';

        reason.category = isRule ? 'Sharing Rule' : (isImplicit ? 'Implicit' : 'Group Share');
        reason.accessLevel = accessLevel;
        reason.confidence = isImplicit ? 'Medium' : 'High';
        reason.isDirect = false;
        reason.sourceName = path.principalName;
        reason.sourceId = path.principalId;
        reason.sourceObject = 'Group';
        reason.principalId = path.principalId;
        reason.principalType = principalGroup != null ? principalGroup.Type : 'Group';
        reason.rowCause = rowCause;
        reason.grantPath = context.prefixedPath(path.renderPath('User'));

        if (isRule) {
            reason.explanation = 'Sharing rule; exact rule name unavailable from the share row. The rule shares the record '
                    + 'with "' + path.principalName + '", of which this user is a member (directly or through nested group membership).';
        } else if (isImplicit) {
            reason.explanation = 'An implicit share row (RowCause = "' + rowCause + '") grants access to "' + path.principalName
                    + '", of which this user is a member. Implicit sharing typically reflects related-record access such as an Account\'s implicit child/parent relationships.';
        } else {
            reason.explanation = 'A share row grants access to "' + path.principalName
                    + '", of which this user is a member (directly or through nested group membership).';
        }
        reason.evidence = 'Share object: ' + context.shareObjectApiName + '; RowCause: ' + rowCause
                + '; AccessLevel: ' + accessLevel + '; Principal: ' + path.principalId;
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
