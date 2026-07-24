import { createElement } from 'lwc';
import RaaRecordAccessExplainer from 'c/raaRecordAccessExplainer';
import hasRunPermission from '@salesforce/apex/RAA_RecordAccessExplainerController.hasRunPermission';
import getDefaultSettings from '@salesforce/apex/RAA_RecordAccessExplainerController.getDefaultSettings';
import startAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.startAnalysis';
import getAnalysisStatus from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisStatus';
import getResults from '@salesforce/apex/RAA_RecordAccessExplainerController.getResults';
import getFieldAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.getFieldAccess';
import getAnalysisDiff from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisDiff';
import getRiskInsights from '@salesforce/apex/RAA_RecordAccessExplainerController.getRiskInsights';
import getPlainEnglishSummary from '@salesforce/apex/RAA_RecordAccessExplainerController.getPlainEnglishSummary';
import { subscribe, unsubscribe } from 'lightning/empApi';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.hasRunPermission',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getDefaultSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.startAnalysis',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getResults',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.cancelAnalysis',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.deleteAnalysis',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.exportResultsCsv',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.exportReasonsCsv',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getFieldAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisDiff',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.startBulkAnalysis',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getBatchRunStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.scanUserAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getUserAccessReasons',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.listMySubscriptions',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.createSubscription',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.setSubscriptionActive',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.deleteSubscription',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getRiskInsights',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getPlainEnglishSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_RESULT = {
    recordId: 'raa001',
    userId: '005000000000001',
    userFullName: 'Jane Doe',
    username: 'jane@example.com',
    userType: 'Standard',
    profileName: 'Standard User',
    isActive: true,
    maxAccessLevel: 'Edit',
    hasReadAccess: true,
    hasEditAccess: true,
    hasDeleteAccess: false,
    hasTransferAccess: false,
    hasAllAccess: false,
    reasonSummary: 'Ownership',
    overallConfidence: 'High',
    hasUnresolvedReason: false,
    reasons: [
        {
            recordId: 'reason001',
            category: 'Ownership',
            accessLevel: 'Full Access',
            confidence: 'High',
            isDirect: true,
            sourceName: 'User',
            rowCause: null,
            grantPath: 'Owner -> User',
            explanation: 'User directly owns this record.',
            evidence: 'Record.OwnerId = 005000000000001'
        }
    ]
};

describe('c-raa-record-access-explainer', () => {
    afterEach(() => {
        jest.clearAllMocks();
        jest.useRealTimers();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        hasRunPermission.mockResolvedValue(true);
        getDefaultSettings.mockResolvedValue({
            defaultIncludeExternalUsers: false,
            defaultIncludeInactiveUsers: false,
            maxUsersPerScan: 0
        });
        const element = createElement('c-raa-record-access-explainer', {
            is: RaaRecordAccessExplainer
        });
        document.body.appendChild(element);
        return element;
    }

    it('shows an unauthorized state when the user lacks the custom permission', async () => {
        hasRunPermission.mockResolvedValue(false);
        getDefaultSettings.mockRejectedValue(new Error('no permission'));
        const element = createElement('c-raa-record-access-explainer', {
            is: RaaRecordAccessExplainer
        });
        document.body.appendChild(element);

        await flushPromises();

        const unauthorizedText = element.shadowRoot.textContent;
        expect(unauthorizedText).toContain('You do not have permission');
    });

    it('shows a validation message for a blank record ID', async () => {
        const element = createComponent();
        await flushPromises();

        const analyzeButton = element.shadowRoot.querySelector(
            '[data-id="analyze-button"]'
        );
        analyzeButton.click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Please enter a record ID'
        );
        expect(startAnalysis).not.toHaveBeenCalled();
    });

    it('shows a validation message for a malformed record ID', async () => {
        const element = createComponent();
        await flushPromises();

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = 'not-valid';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));

        const analyzeButton = element.shadowRoot.querySelector(
            '[data-id="analyze-button"]'
        );
        analyzeButton.click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'does not look like a valid'
        );
        expect(startAnalysis).not.toHaveBeenCalled();
    });

    it('starts a scan for a valid record ID and shows progress', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Running',
            totalUsers: 10,
            processedUsers: 2,
            usersWithAccess: 1,
            isComplete: false,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getAnalysisStatus.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Running',
            totalUsers: 10,
            processedUsers: 4,
            usersWithAccess: 2,
            isComplete: false
        });

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));

        const analyzeButton = element.shadowRoot.querySelector(
            '[data-id="analyze-button"]'
        );
        analyzeButton.click();
        await flushPromises();

        expect(startAnalysis).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Running');
    });

    it('polls for status until a terminal state and then loads results', async () => {
        jest.useFakeTimers();

        hasRunPermission.mockResolvedValue(true);
        getDefaultSettings.mockResolvedValue({
            defaultIncludeExternalUsers: false,
            defaultIncludeInactiveUsers: false,
            maxUsersPerScan: 0
        });
        const element = createElement('c-raa-record-access-explainer', {
            is: RaaRecordAccessExplainer
        });
        document.body.appendChild(element);
        await jest.advanceTimersByTimeAsync(0);

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Running',
            totalUsers: 1,
            processedUsers: 0,
            usersWithAccess: 0,
            isComplete: false
        });

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await jest.advanceTimersByTimeAsync(0);

        getAnalysisStatus.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        await jest.advanceTimersByTimeAsync(10000);

        expect(getAnalysisStatus).toHaveBeenCalled();
        expect(getResults).toHaveBeenCalled();
    });

    it('renders completed results in the datatable and opens the reason detail modal', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(1);

        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action: { name: 'view_reasons' }, row: SAMPLE_RESULT }
            })
        );
        await flushPromises();

        const detail = element.shadowRoot.querySelector('c-raa-reason-detail');
        expect(detail).not.toBeNull();
        expect(detail.reasons).toHaveLength(1);
    });

    it('shows the potentially-incomplete warning banner when warnings are present', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed with Warnings',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            warnings: 'Territory analysis could not be completed.',
            potentiallyIncomplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([]);

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Potentially Incomplete'
        );
        expect(element.shadowRoot.textContent).toContain(
            'Territory analysis could not be completed'
        );
    });

    it('shows a sanitized error message when the server call fails', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockRejectedValue({
            body: { message: 'You do not have access to this record type.' }
        });

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'You do not have access to this record type.'
        );
    });

    it('switches to bulk mode and hides the single-record form', async () => {
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-raa-bulk-scan')).toBeNull();

        element.shadowRoot.querySelector('[data-mode="bulk"]').click();
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-raa-bulk-scan')
        ).not.toBeNull();
        expect(
            element.shadowRoot.querySelector('[data-id="record-id-input"]')
        ).toBeNull();
    });

    it('switches to by-user mode', async () => {
        const element = createComponent();
        await flushPromises();

        element.shadowRoot.querySelector('[data-mode="byUser"]').click();
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-raa-user-access-explorer')
        ).not.toBeNull();
    });

    it('switches to subscriptions mode', async () => {
        const element = createComponent();
        await flushPromises();

        element.shadowRoot.querySelector('[data-mode="subscriptions"]').click();
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-raa-subscriptions')
        ).not.toBeNull();
    });

    it('switches to risk insights mode', async () => {
        const element = createComponent();
        await flushPromises();

        element.shadowRoot.querySelector('[data-mode="riskInsights"]').click();
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-raa-risk-insights')
        ).not.toBeNull();
    });

    it('switches back to single mode and loads the analysis when a risk insights row is opened', async () => {
        const element = createComponent();
        await flushPromises();

        getRiskInsights.mockResolvedValue([
            {
                analysisId: 'a00000000000003',
                recordId: '001000000000003AAA',
                objectApiName: 'Account',
                recordDisplayName: 'From Risk Insights',
                completedAt: '2026-07-20T00:00:00.000Z',
                usersWithAccess: 4,
                externalUserCount: 2,
                bypassHolderCount: 0,
                unresolvedCount: 0,
                riskScore: 6
            }
        ]);
        getAnalysisStatus.mockResolvedValue({
            analysisId: 'a00000000000003',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'From Risk Insights'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        element.shadowRoot.querySelector('[data-mode="riskInsights"]').click();
        await flushPromises();

        const riskInsights = element.shadowRoot.querySelector(
            'c-raa-risk-insights'
        );
        riskInsights.dispatchEvent(
            new CustomEvent('viewanalysis', {
                detail: { analysisId: 'a00000000000003' }
            })
        );
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('c-raa-risk-insights')
        ).toBeNull();
        expect(getAnalysisStatus).toHaveBeenCalledWith({
            analysisId: 'a00000000000003'
        });
        expect(element.shadowRoot.textContent).toContain('From Risk Insights');
    });

    it('switches back to single mode and loads the analysis when a bulk row is opened', async () => {
        const element = createComponent();
        await flushPromises();

        getAnalysisStatus.mockResolvedValue({
            analysisId: 'a00000000000002',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'From Bulk'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        element.shadowRoot.querySelector('[data-mode="bulk"]').click();
        await flushPromises();

        const bulkScan = element.shadowRoot.querySelector('c-raa-bulk-scan');
        bulkScan.dispatchEvent(
            new CustomEvent('viewanalysis', {
                detail: { analysisId: 'a00000000000002' }
            })
        );
        await flushPromises();

        expect(element.shadowRoot.querySelector('c-raa-bulk-scan')).toBeNull();
        expect(getAnalysisStatus).toHaveBeenCalledWith({
            analysisId: 'a00000000000002'
        });
        expect(element.shadowRoot.textContent).toContain('From Bulk');
    });

    it('opens the field access modal from a row action', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        getFieldAccess.mockResolvedValue([]);
        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_field_access' },
                    row: SAMPLE_RESULT
                }
            })
        );
        await flushPromises();

        const fieldAccess =
            element.shadowRoot.querySelector('c-raa-field-access');
        expect(fieldAccess).not.toBeNull();
        expect(fieldAccess.userId).toBe(SAMPLE_RESULT.userId);
        expect(fieldAccess.objectApiName).toBe('Account');

        fieldAccess.dispatchEvent(new CustomEvent('close'));
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('c-raa-field-access')
        ).toBeNull();
    });

    it('opens the compare-to-previous-scan diff modal', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        getAnalysisDiff.mockResolvedValue(null);
        const buttons = [
            ...element.shadowRoot.querySelectorAll('lightning-button')
        ];
        const diffButton = buttons.find(
            (b) => b.label === 'Compare to Previous Scan'
        );
        diffButton.click();
        await flushPromises();

        const diffModal = element.shadowRoot.querySelector(
            'c-raa-analysis-diff'
        );
        expect(diffModal).not.toBeNull();
        expect(diffModal.analysisId).toBe('a00000000000001');

        diffModal.dispatchEvent(new CustomEvent('close'));
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('c-raa-analysis-diff')
        ).toBeNull();
    });

    it('opens the plain-english summary modal', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([SAMPLE_RESULT]);

        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        getPlainEnglishSummary.mockResolvedValue(
            '1 user has access to Acme Corp (Account).'
        );
        const buttons = [
            ...element.shadowRoot.querySelectorAll('lightning-button')
        ];
        const summaryButton = buttons.find(
            (b) => b.label === 'Plain-English Summary'
        );
        summaryButton.click();
        await flushPromises();

        const summaryModal = element.shadowRoot.querySelector(
            'c-raa-plain-english-summary'
        );
        expect(summaryModal).not.toBeNull();
        expect(summaryModal.analysisId).toBe('a00000000000001');

        summaryModal.dispatchEvent(new CustomEvent('close'));
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('c-raa-plain-english-summary')
        ).toBeNull();
    });

    it('subscribes to the scan status event channel on connect', async () => {
        createComponent();
        await flushPromises();

        expect(subscribe).toHaveBeenCalledWith(
            '/event/RAA_Scan_Status_Event__e',
            -1,
            expect.any(Function)
        );
    });

    it('refreshes status when a matching scan status event arrives', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Running',
            totalUsers: 1,
            processedUsers: 0,
            usersWithAccess: 0,
            isComplete: false
        });
        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();

        getAnalysisStatus.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Completed',
            totalUsers: 1,
            processedUsers: 1,
            usersWithAccess: 1,
            isComplete: true,
            objectApiName: 'Account',
            recordDisplayName: 'Acme Corp'
        });
        getResults.mockResolvedValue([]);

        const eventHandler = subscribe.mock.calls[0][2];
        eventHandler({
            data: { payload: { RAA_Analysis_Id__c: 'a00000000000001' } }
        });
        await flushPromises();

        expect(getAnalysisStatus).toHaveBeenCalledWith({
            analysisId: 'a00000000000001'
        });
    });

    it('ignores a scan status event for a different analysis', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockResolvedValue({
            analysisId: 'a00000000000001',
            status: 'Running',
            totalUsers: 1,
            processedUsers: 0,
            usersWithAccess: 0,
            isComplete: false
        });
        const input = element.shadowRoot.querySelector(
            '[data-id="record-id-input"]'
        );
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();

        getAnalysisStatus.mockClear();
        const eventHandler = subscribe.mock.calls[0][2];
        eventHandler({
            data: { payload: { RAA_Analysis_Id__c: 'a09999999999999' } }
        });
        await flushPromises();

        expect(getAnalysisStatus).not.toHaveBeenCalled();
    });

    it('unsubscribes from the scan status channel when removed from the DOM', async () => {
        const element = createComponent();
        await flushPromises();

        document.body.removeChild(element);
        await flushPromises();

        expect(unsubscribe).toHaveBeenCalled();
    });
});
