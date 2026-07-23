import { createElement } from 'lwc';
import RaaRecordAccessExplainer from 'c/raaRecordAccessExplainer';
import hasRunPermission from '@salesforce/apex/RAA_RecordAccessExplainerController.hasRunPermission';
import getDefaultSettings from '@salesforce/apex/RAA_RecordAccessExplainerController.getDefaultSettings';
import startAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.startAnalysis';
import getAnalysisStatus from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisStatus';
import getResults from '@salesforce/apex/RAA_RecordAccessExplainerController.getResults';

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
        const element = createElement('c-raa-record-access-explainer', { is: RaaRecordAccessExplainer });
        document.body.appendChild(element);
        return element;
    }

    it('shows an unauthorized state when the user lacks the custom permission', async () => {
        hasRunPermission.mockResolvedValue(false);
        getDefaultSettings.mockRejectedValue(new Error('no permission'));
        const element = createElement('c-raa-record-access-explainer', { is: RaaRecordAccessExplainer });
        document.body.appendChild(element);

        await flushPromises();

        const unauthorizedText = element.shadowRoot.textContent;
        expect(unauthorizedText).toContain('You do not have permission');
    });

    it('shows a validation message for a blank record ID', async () => {
        const element = createComponent();
        await flushPromises();

        const analyzeButton = element.shadowRoot.querySelector('[data-id="analyze-button"]');
        analyzeButton.click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Please enter a record ID');
        expect(startAnalysis).not.toHaveBeenCalled();
    });

    it('shows a validation message for a malformed record ID', async () => {
        const element = createComponent();
        await flushPromises();

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
        input.value = 'not-valid';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));

        const analyzeButton = element.shadowRoot.querySelector('[data-id="analyze-button"]');
        analyzeButton.click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('does not look like a valid');
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

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));

        const analyzeButton = element.shadowRoot.querySelector('[data-id="analyze-button"]');
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
        const element = createElement('c-raa-record-access-explainer', { is: RaaRecordAccessExplainer });
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

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
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

        await jest.advanceTimersByTimeAsync(3000);

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

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(1);

        datatable.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'view_reasons' }, row: SAMPLE_RESULT } }));
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

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Potentially Incomplete');
        expect(element.shadowRoot.textContent).toContain('Territory analysis could not be completed');
    });

    it('shows a sanitized error message when the server call fails', async () => {
        const element = createComponent();
        await flushPromises();

        startAnalysis.mockRejectedValue({ body: { message: 'You do not have access to this record type.' } });

        const input = element.shadowRoot.querySelector('[data-id="record-id-input"]');
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change', { detail: {} }));
        element.shadowRoot.querySelector('[data-id="analyze-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('You do not have access to this record type.');
    });
});
