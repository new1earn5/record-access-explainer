/**
 * Detects access granted through Enterprise Territory Management. Territory2,
 * UserTerritory2Association, and ObjectTerritory2Association are only referenced through fully
 * dynamic SOQL (never a compile-time sObject type), because those objects do not exist at all
 * in orgs where Enterprise Territory Management has never been enabled - a static reference
 * would break deployment for every org without that feature. When the feature is not present,
 * this analyzer silently contributes nothing rather than raising a warning, since territory
 * analysis is simply not applicable there.
 */
public without sharing class RAA_TerritoryAnalyzer implements RAA_IReasonAnalyzer {
    public String getAnalyzerName() {
        return 'Territory Management';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (userIds == null || userIds.isEmpty() || !territoryManagementAvailable()) {
            return results;
        }

        try {
            Id accountId = resolveAccountId(context);
            if (accountId == null) {
                return results;
            }

            Set<Id> directTerritoryIds = new Set<Id>();
            for (
                SObject assoc : Database.query(
                    'SELECT Territory2Id FROM ObjectTerritory2Association WHERE ObjectId = :accountId'
                )
            ) {
                directTerritoryIds.add((Id) assoc.get('Territory2Id'));
            }
            if (directTerritoryIds.isEmpty()) {
                return results;
            }

            Map<Id, Id> parentByTerritory = new Map<Id, Id>();
            Map<Id, String> nameByTerritory = new Map<Id, String>();
            for (SObject territory : Database.query('SELECT Id, Name, ParentTerritory2Id FROM Territory2')) {
                parentByTerritory.put((Id) territory.get('Id'), (Id) territory.get('ParentTerritory2Id'));
                nameByTerritory.put((Id) territory.get('Id'), (String) territory.get('Name'));
            }

            Set<Id> ancestorTerritoryIds = new Set<Id>();
            for (Id start : directTerritoryIds) {
                Id cursor = parentByTerritory.get(start);
                Integer guard = 0;
                while (cursor != null && !ancestorTerritoryIds.contains(cursor) && guard < 100) {
                    ancestorTerritoryIds.add(cursor);
                    cursor = parentByTerritory.get(cursor);
                    guard++;
                }
            }

            Set<Id> allRelevantTerritoryIds = new Set<Id>(directTerritoryIds);
            allRelevantTerritoryIds.addAll(ancestorTerritoryIds);

            for (
                SObject uta : Database.query(
                    'SELECT UserId, Territory2Id FROM UserTerritory2Association WHERE UserId IN :userIds AND Territory2Id IN :allRelevantTerritoryIds'
                )
            ) {
                Id userId = (Id) uta.get('UserId');
                Id territoryId = (Id) uta.get('Territory2Id');
                Boolean isDirectTerritory = directTerritoryIds.contains(territoryId);
                String territoryName = nameByTerritory.get(territoryId);

                RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
                reason.category = 'Territory';
                reason.accessLevel = null;
                reason.confidence = isDirectTerritory ? 'High' : 'Medium';
                reason.isDirect = false;
                reason.sourceName = 'Territory: ' + territoryName;
                reason.sourceId = territoryId;
                reason.sourceObject = 'Territory2';
                reason.principalId = territoryId;
                reason.principalType = isDirectTerritory ? 'Territory2' : 'Territory2AndSubordinates';
                reason.rowCause = null;
                reason.grantPath = context.prefixedPath(
                    (isDirectTerritory ? 'Territory: ' : 'Territory (subordinate): ') + territoryName + ' -> User'
                );
                reason.explanation = isDirectTerritory
                    ? 'The user is assigned to territory "' +
                      territoryName +
                      '", which is directly associated with this account.'
                    : 'The user is assigned to territory "' +
                      territoryName +
                      '", an ancestor of a territory directly associated with this account, so subordinate territory access may apply.';
                reason.explanation += ' The exact access level enforced by the territory model could not be independently confirmed through a supported API, so no specific access level is shown.';
                reason.evidence = 'AccountId: ' + accountId + '; Territory2Id: ' + territoryId;

                addReason(results, userId, reason);
            }
        } catch (System.QueryException e) {
            context.warnings.add('Territory analysis could not be completed: ' + e.getMessage());
        }

        return results;
    }

    private Boolean territoryManagementAvailable() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        return globalDescribe.containsKey('Territory2') &&
            globalDescribe.containsKey('UserTerritory2Association') &&
            globalDescribe.containsKey('ObjectTerritory2Association');
    }

    private Id resolveAccountId(RAA_AnalysisContext context) {
        if (context.objectApiName == 'Account') {
            return context.recordId;
        }
        Map<String, Schema.SObjectField> fieldMap = context.objectDescribe.fields.getMap();
        if (!fieldMap.containsKey('AccountId')) {
            return null;
        }
        Id recordId = context.recordId;
        List<SObject> rows = Database.query(
            'SELECT AccountId FROM ' +
                String.escapeSingleQuotes(context.objectApiName) +
                ' WHERE Id = :recordId LIMIT 1'
        );
        if (rows.isEmpty() || rows[0].get('AccountId') == null) {
            return null;
        }
        return (Id) rows[0].get('AccountId');
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
