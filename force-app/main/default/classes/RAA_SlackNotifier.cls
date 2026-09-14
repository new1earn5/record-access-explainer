/**
 * Sends Slack change-alert notifications via an Incoming Webhook URL. Validation and the
 * callout both live here so the two are never out of sync.
 *
 * The URL is restricted to https://hooks.slack.com/ at two independent layers: the format check
 * in validateWebhookUrl (a clear, immediate error at subscription-creation time) and the
 * RAA_Slack_Webhooks Remote Site Setting, which Salesforce enforces as an allowlist for every
 * outbound callout regardless of what's stored in RAA_Slack_Webhook_URL__c. Either one alone
 * would prevent this field from being usable as an open callout to an arbitrary host; both
 * together mean a bug in one doesn't depend on the other.
 */
public without sharing class RAA_SlackNotifier {
    @TestVisible
    private static final String ALLOWED_PREFIX = 'https://hooks.slack.com/';

    public static void validateWebhookUrl(String webhookUrl) {
        if (String.isBlank(webhookUrl) || !webhookUrl.startsWith(ALLOWED_PREFIX)) {
            throw new RAA_AppException('Slack Webhook URL must start with ' + ALLOWED_PREFIX);
        }
    }

    public static void postMessage(String webhookUrl, String messageText) {
        validateWebhookUrl(webhookUrl);

        HttpRequest request = new HttpRequest();
        request.setEndpoint(webhookUrl);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(new Map<String, String>{ 'text' => messageText }));

        Http http = new Http();
        HttpResponse response = http.send(request);
        if (response.getStatusCode() != 200) {
            throw new RAA_AppException('Slack webhook call failed with status ' + response.getStatusCode());
        }
    }
}
