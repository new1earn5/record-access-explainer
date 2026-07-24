/**
 * Optional recurring-scan scheduler. Not scheduled automatically on install; an administrator
 * opts in (see README). Each firing does two things: (1) for any subscription whose previous
 * cycle's scan has now completed, compares it against the prior baseline and, if anything
 * changed, emails the subscriber (RAA_Notify_On_Change__c) and/or posts a Chatter update on the
 * watched record (RAA_Post_To_Chatter__c) - independently, either or both; (2) starts a new scan
 * for every active subscription that isn't already waiting on one. This means a notification is
 * sent on the scheduled run *after* the one that started the scan, once that scan has had time to
 * complete - by design, so this never blocks on a long-running scan.
 */
// Deliberately without sharing and CRUD/FLS-unchecked: a scheduled job operating on the
// package's own subscription/analysis data (see README.md §1, "Batch Apex runs in system
// mode"), not reachable from the client.
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RAA_RecurringScanScheduler implements Schedulable {
    @TestVisible
    private static final Integer MAX_SUBSCRIPTIONS_PER_RUN = 200;

    public void execute(SchedulableContext sc) {
        RAA_SubscriptionRepository subscriptionRepo = new RAA_SubscriptionRepository();
        RAA_AnalysisRepository analysisRepo = new RAA_AnalysisRepository();
        RAA_AnalysisDiffService diffService = new RAA_AnalysisDiffService();

        List<RAA_Scan_Subscription__c> subscriptions = subscriptionRepo.getActiveSubscriptions(
            MAX_SUBSCRIPTIONS_PER_RUN
        );

        List<Id> readyToStart = new List<Id>();
        for (RAA_Scan_Subscription__c subscription : subscriptions) {
            if (subscription.RAA_Pending_Analysis__c == null) {
                readyToStart.add(subscription.Id);
                continue;
            }

            RAA_Analysis__c pendingAnalysis = analysisRepo.getAnalysis(subscription.RAA_Pending_Analysis__c);
            if (pendingAnalysis == null || !pendingAnalysis.RAA_Is_Complete__c) {
                continue; // still running from the previous cycle; check again next time
            }

            processCompletedCycle(subscription, pendingAnalysis, diffService, subscriptionRepo);
        }

        if (!readyToStart.isEmpty()) {
            System.enqueueJob(new RAA_SubscriptionScanQueueable(readyToStart));
        }
    }

    // The empty catch below (sendChangeNotification) is deliberate: see its own inline comment.
    @SuppressWarnings('PMD.EmptyCatchBlock')
    @TestVisible
    private void processCompletedCycle(
        RAA_Scan_Subscription__c subscription,
        RAA_Analysis__c pendingAnalysis,
        RAA_AnalysisDiffService diffService,
        RAA_SubscriptionRepository subscriptionRepo
    ) {
        Boolean wantsAnyNotification = subscription.RAA_Notify_On_Change__c || subscription.RAA_Post_To_Chatter__c;
        if (subscription.RAA_Last_Analysis__c != null && wantsAnyNotification) {
            try {
                RAA_AnalysisDiffDTO diff = diffService.compare(subscription.RAA_Last_Analysis__c, pendingAnalysis.Id);
                if (diff != null && !diff.changes.isEmpty()) {
                    if (subscription.RAA_Notify_On_Change__c) {
                        sendChangeNotification(subscription, diff);
                    }
                    if (subscription.RAA_Post_To_Chatter__c) {
                        postChatterUpdate(subscription, diff);
                    }
                }
            } catch (Exception e) {
                // A notification failure must never block the baseline from advancing.
            }
        }
        subscriptionRepo.advanceBaseline(subscription.Id, pendingAnalysis.Id);
    }

    private void sendChangeNotification(RAA_Scan_Subscription__c subscription, RAA_AnalysisDiffDTO diff) {
        if (subscription.RAA_Subscriber__c == null) {
            return;
        }
        List<User> recipients = [
            SELECT Id, Email
            FROM User
            WHERE Id = :subscription.RAA_Subscriber__c AND IsActive = TRUE
            LIMIT 1
        ];
        if (recipients.isEmpty() || String.isBlank(recipients[0].Email)) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ recipients[0].Email });
        email.setSubject(
            'Record Access Explainer: access change detected for ' + subscription.RAA_Record_Display_Name__c
        );
        email.setPlainTextBody(buildEmailBody(subscription, diff));
        email.setSaveAsActivity(false);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }

    // RestrictionRule-style defensive probe: FeedItem/Chatter Feed Tracking may not be enabled
    // for the watched object, which surfaces as an insert failure, not a describe-absence - a
    // failed post must never block the email notification (already sent above, if enabled) or
    // the baseline advance in the caller's own catch.
    @SuppressWarnings('PMD.EmptyCatchBlock')
    private void postChatterUpdate(RAA_Scan_Subscription__c subscription, RAA_AnalysisDiffDTO diff) {
        if (!Schema.getGlobalDescribe().containsKey('FeedItem')) {
            return;
        }
        try {
            FeedItem post = new FeedItem(
                ParentId = subscription.RAA_Record_Id__c,
                Body = buildChatterBody(subscription, diff)
            );
            insert post;
        } catch (Exception e) {
            // Chatter Feed Tracking is likely not enabled for this object; nothing further to do.
        }
    }

    private String buildChatterBody(RAA_Scan_Subscription__c subscription, RAA_AnalysisDiffDTO diff) {
        List<String> lines = new List<String>();
        lines.add(
            'Record Access Explainer detected an access change on this record: ' +
                diff.usersAdded +
                ' user(s) gained access, ' +
                diff.usersRemoved +
                ' user(s) lost access, ' +
                diff.usersChanged +
                ' user(s) had their access change.'
        );
        Integer previewCount = Math.min(5, diff.changes.size());
        for (Integer i = 0; i < previewCount; i++) {
            RAA_UserAccessChangeDTO change = diff.changes[i];
            lines.add('- ' + change.changeType + ': ' + change.userFullName);
        }
        if (diff.changes.size() > previewCount) {
            lines.add(
                '...and ' +
                    (diff.changes.size() - previewCount) +
                    ' more. See Record Access Explainer for full details.'
            );
        }
        return String.join(lines, '\n');
    }

    private String buildEmailBody(RAA_Scan_Subscription__c subscription, RAA_AnalysisDiffDTO diff) {
        List<String> lines = new List<String>();
        lines.add(
            'Record Access Explainer detected an access change for "' +
                subscription.RAA_Record_Display_Name__c +
                '" (' +
                subscription.RAA_Object_API_Name__c +
                ').'
        );
        lines.add('');
        lines.add(
            diff.usersAdded +
                ' user(s) gained access, ' +
                diff.usersRemoved +
                ' user(s) lost access, ' +
                diff.usersChanged +
                ' user(s) had their access change.'
        );
        lines.add('');
        for (RAA_UserAccessChangeDTO change : diff.changes) {
            lines.add('- ' + change.changeType + ': ' + change.userFullName + ' (' + change.username + ')');
        }
        lines.add('');
        lines.add('Open Record Access Explainer in Salesforce to see full details.');
        return String.join(lines, '\n');
    }
}
