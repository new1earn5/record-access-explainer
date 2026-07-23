import { createElement } from 'lwc';
import RaaBulkScan from 'c/raaBulkScan';
import startBulkAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.startBulkAnalysis';
import getBatchRunStatus from '@salesforce/apex/RAA_RecordAccessExplainerController.getBatchRunStatus';

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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const RUNNING_BATCH = {
    batchRunId: 'b00000000000001',
    status: 'Running',
    totalRecords: 2,
    completedRecords: 1,
    analyses: [{ analysisId: 'a1', recordDisplayName: 'Acme', status: 'Completed', usersWithAccess: 3 }]
};

const COMPLETED_BATCH = {
    batchRunId: 'b00000000000001',
    status: 'Completed',
    totalRecords: 2,
    completedRecords: 2,
    analyses: [
        { analysisId: 'a1', recordDisplayName: 'Acme', status: 'Completed', usersWithAccess: 3 },
        { analysisId: 'a2', recordDisplayName: 'Globex', status: 'Completed', usersWithAccess: 5 }
    ]
};

describe('c-raa-bulk-scan', () => {
    afterEach(() => {
        jest.clearAllMocks();
        jest.useRealTimers();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-bulk-scan', { is: RaaBulkScan });
        document.body.appendChild(element);
        return element;
    }

    it('shows a validation message when no record IDs are entered', async () => {
        const element = createComponent();

        element.shadowRoot.querySelector('[data-id="bulk-start-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Enter at least one record ID');
        expect(startBulkAnalysis).not.toHaveBeenCalled();
    });

    it('parses newline and comma separated IDs and starts the bulk scan', async () => {
        startBulkAnalysis.mockResolvedValue(RUNNING_BATCH);
        const element = createComponent();

        const textarea = element.shadowRoot.querySelector('[data-id="bulk-record-ids"]');
        textarea.value = '001000000000001AAA,001000000000002AAA\n001000000000003AAA';
        textarea.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot.querySelector('[data-id="bulk-start-button"]').click();
        await flushPromises();

        expect(startBulkAnalysis).toHaveBeenCalledWith({
            recordIds: ['001000000000001AAA', '001000000000002AAA', '001000000000003AAA'],
            includeExternalUsers: false,
            includeInactiveUsers: false
        });
        expect(element.shadowRoot.textContent).toContain('Running');
    });

    it('polls for status and renders the datatable once results come back', async () => {
        jest.useFakeTimers();
        startBulkAnalysis.mockResolvedValue(RUNNING_BATCH);
        getBatchRunStatus.mockResolvedValue(COMPLETED_BATCH);

        const element = createComponent();
        const textarea = element.shadowRoot.querySelector('[data-id="bulk-record-ids"]');
        textarea.value = '001000000000001AAA\n001000000000002AAA';
        textarea.dispatchEvent(new CustomEvent('change'));
        element.shadowRoot.querySelector('[data-id="bulk-start-button"]').click();
        await jest.advanceTimersByTimeAsync(0);

        await jest.advanceTimersByTimeAsync(4000);

        expect(getBatchRunStatus).toHaveBeenCalledWith({ batchRunId: 'b00000000000001' });
        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        expect(datatable.data).toHaveLength(2);
    });

    it('dispatches viewanalysis when a row action is triggered', async () => {
        startBulkAnalysis.mockResolvedValue(COMPLETED_BATCH);
        const element = createComponent();

        const textarea = element.shadowRoot.querySelector('[data-id="bulk-record-ids"]');
        textarea.value = '001000000000001AAA';
        textarea.dispatchEvent(new CustomEvent('change'));
        element.shadowRoot.querySelector('[data-id="bulk-start-button"]').click();
        await flushPromises();

        const viewHandler = jest.fn();
        element.addEventListener('viewanalysis', viewHandler);

        const datatable = element.shadowRoot.querySelector('lightning-datatable');
        datatable.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'view_analysis' }, row: { analysisId: 'a1' } } }));

        expect(viewHandler).toHaveBeenCalled();
        expect(viewHandler.mock.calls[0][0].detail.analysisId).toBe('a1');
    });

    it('resets back to the form on New Bulk Scan', async () => {
        startBulkAnalysis.mockResolvedValue(COMPLETED_BATCH);
        const element = createComponent();

        const textarea = element.shadowRoot.querySelector('[data-id="bulk-record-ids"]');
        textarea.value = '001000000000001AAA';
        textarea.dispatchEvent(new CustomEvent('change'));
        element.shadowRoot.querySelector('[data-id="bulk-start-button"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="bulk-record-ids"]')).toBeNull();

        const buttons = [...element.shadowRoot.querySelectorAll('lightning-button')];
        const newScanButton = buttons.find((b) => b.label === 'New Bulk Scan');
        newScanButton.click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="bulk-record-ids"]')).not.toBeNull();
    });
});
