import { createElement } from 'lwc';
import RaaRiskInsights from 'c/raaRiskInsights';
import getRiskInsights from '@salesforce/apex/RAA_RecordAccessExplainerController.getRiskInsights';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getRiskInsights',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_INSIGHT = {
    analysisId: 'a00000000000001',
    recordId: '001000000000001AAA',
    objectApiName: 'Account',
    recordDisplayName: 'Acme Corp',
    completedAt: '2026-07-20T00:00:00.000Z',
    usersWithAccess: 12,
    externalUserCount: 3,
    bypassHolderCount: 1,
    unresolvedCount: 0,
    riskScore: 11
};

describe('c-raa-risk-insights', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-risk-insights', {
            is: RaaRiskInsights
        });
        document.body.appendChild(element);
        return element;
    }

    it('loads insights on connect and shows the empty state when there are none', async () => {
        getRiskInsights.mockResolvedValue([]);
        const element = createComponent();
        await flushPromises();

        expect(getRiskInsights).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain(
            'No completed scans yet'
        );
    });

    it('renders ranked insights in the datatable', async () => {
        getRiskInsights.mockResolvedValue([SAMPLE_INSIGHT]);
        const element = createComponent();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(1);
        expect(datatable.data[0].riskScore).toBe(11);
    });

    it('dispatches viewanalysis when the View Analysis row action is triggered', async () => {
        getRiskInsights.mockResolvedValue([SAMPLE_INSIGHT]);
        const element = createComponent();
        await flushPromises();

        const viewHandler = jest.fn();
        element.addEventListener('viewanalysis', viewHandler);

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_analysis' },
                    row: SAMPLE_INSIGHT
                }
            })
        );

        expect(viewHandler).toHaveBeenCalled();
        expect(viewHandler.mock.calls[0][0].detail.analysisId).toBe(
            'a00000000000001'
        );
    });

    it('reloads insights when Refresh is clicked', async () => {
        getRiskInsights.mockResolvedValue([]);
        const element = createComponent();
        await flushPromises();

        const refreshButton = [
            ...element.shadowRoot.querySelectorAll('lightning-button')
        ].find((b) => b.label === 'Refresh');
        refreshButton.click();
        await flushPromises();

        expect(getRiskInsights).toHaveBeenCalledTimes(2);
    });

    it('shows an error toast when the Apex call fails', async () => {
        getRiskInsights.mockRejectedValue({
            body: { message: 'No permission.' }
        });
        const handler = jest.fn();
        const element = createComponent();
        element.addEventListener('lightning__showtoast', handler);
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.message).toBe('No permission.');
    });
});
