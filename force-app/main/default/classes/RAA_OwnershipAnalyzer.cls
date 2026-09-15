/**
 * Detects access granted because a candidate user is the record owner, or is a member of the
 * queue that owns the record. Confidence is always High because ownership and queue membership
 * are directly queryable facts.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: part of the elevated scan pipeline (see
// docs/architecture.md §1, "Batch Apex runs in system mode"), reached only through the with-sharing
// controller's permission and per-record visibility gate.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_OwnershipAnalyzer implements RAA_IReasonAnalyzer {
    private final RAA_GroupGraphResolver groupResolver;

    public RAA_OwnershipAnalyzer() {
        this(new RAA_GroupGraphResolver());
    }

    public RAA_OwnershipAnalyzer(RAA_GroupGraphResolver groupResolver) {
        this.groupResolver = groupResolver;
    }

    public String getAnalyzerName() {
        return 'Ownership';
    }

    public Map<Id, List<RAA_AccessReasonDTO>> analyze(RAA_AnalysisContext context, Set<Id> userIds) {
        Map<Id, List<RAA_AccessReasonDTO>> results = new Map<Id, List<RAA_AccessReasonDTO>>();
        if (context.ownerId == null) {
            return results;
        }

        Schema.SObjectType ownerType = context.ownerId.getSObjectType();

        if (ownerType == User.SObjectType) {
            if (userIds.contains(context.ownerId)) {
                addReason(
                    results,
                    context.ownerId,
                    buildReason(
                        context,
                        'Full Access',
                        true,
                        'User',
                        context.ownerId,
                        'User',
                        context.ownerId,
                        'User',
                        'User directly owns this record.',
                        context.prefixedPath('Owner -> User')
                    )
                );
            }
            return results;
        }

        if (ownerType == Group.SObjectType) {
            List<Group> queues = [SELECT Id, Name, Type FROM Group WHERE Id = :context.ownerId LIMIT 1];
            if (queues.isEmpty() || queues[0].Type != 'Queue') {
                return results;
            }
            Group queue = queues[0];
            Map<Id, List<RAA_GroupPathDTO>> paths = groupResolver.resolvePaths(
                new Set<Id>{ context.ownerId },
                userIds,
                context.maxGroupDepth
            );

            for (Id userId : paths.keySet()) {
                for (RAA_GroupPathDTO path : paths.get(userId)) {
                    String renderedPath = context.prefixedPath('Owner (Queue) -> ' + path.renderPath('User'));
                    addReason(
                        results,
                        userId,
                        buildReason(
                            context,
                            'Full Access',
                            path.pathSegments.size() == 1,
                            'Queue: ' + queue.Name,
                            queue.Id,
                            'Group',
                            queue.Id,
                            'Queue',
                            'Record is owned by queue "' + queue.Name + '", and the user belongs to that queue.',
                            renderedPath
                        )
                    );
                }
            }
            return results;
        }

        // Owner is neither a User nor a Group: no supported ownership mechanism to report.
        return results;
    }

    private RAA_AccessReasonDTO buildReason(
        RAA_AnalysisContext context,
        String accessLevel,
        Boolean isDirect,
        String sourceName,
        Id sourceId,
        String sourceObject,
        Id principalId,
        String principalType,
        String explanation,
        String grantPath
    ) {
        RAA_AccessReasonDTO reason = new RAA_AccessReasonDTO();
        reason.category = 'Ownership';
        reason.accessLevel = accessLevel;
        reason.confidence = 'High';
        reason.isDirect = isDirect;
        reason.sourceName = sourceName;
        reason.sourceId = sourceId;
        reason.sourceObject = sourceObject;
        reason.principalId = principalId;
        reason.principalType = principalType;
        reason.rowCause = null;
        reason.grantPath = grantPath;
        reason.explanation = explanation;
        reason.evidence = 'Record.OwnerId = ' + context.ownerId;
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
