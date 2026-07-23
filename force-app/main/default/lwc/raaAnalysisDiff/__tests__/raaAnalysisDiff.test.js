import { createElement } from 'lwc';
import RaaAnalysisDiff from 'c/raaAnalysisDiff';
import getAnalysisDiff from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisDiff';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisDiff',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-raa-analysis-diff', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-analysis-diff', { is: RaaAnalysisDiff });
        element.analysisId = 'a00000000000001';
        element.recordDisplayName = 'Acme Corp';
        document.body.appendChild(element);
        return element;
    }

    it('shows the no-previous-analysis message on the first scan', async () => {
        getAnalysisDiff.mockResolvedValue(null);
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('no earlier completed scan');
    });

    it('shows the no-changes message when nothing differs', async () => {
        getAnalysisDiff.mockResolvedValue({ usersAdded: 0, usersRemoved: 0, usersChanged: 0, changes: [] });
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('No differences were found');
    });

    it('renders each change with the correct badge class', async () => {
        getAnalysisDiff.mockResolvedValue({
            usersAdded: 1,
            usersRemoved: 1,
            usersChanged: 1,
            changes: [
                { changeType: 'Added', userFullName: 'A User', username: 'a@example.com', previousMaxAccessLevel: null, currentMaxAccessLevel: 'Read', previousReasonSummary: null, currentReasonSummary: 'Ownership' },
                { changeType: 'Removed', userFullName: 'B User', username: 'b@example.com', previousMaxAccessLevel: 'Read', currentMaxAccessLevel: null, previousReasonSummary: 'Ownership', currentReasonSummary: null },
                { changeType: 'Changed', userFullName: 'C User', username: 'c@example.com', previousMaxAccessLevel: 'Read', currentMaxAccessLevel: 'Edit', previousReasonSummary: 'Ownership', currentReasonSummary: 'Ownership, Permission' }
            ]
        });

        const element = createComponent();
        await flushPromises();

        const articles = element.shadowRoot.querySelectorAll('article');
        expect(articles).toHaveLength(3);
        expect(element.shadowRoot.textContent).toContain('1 gained access');

        const badges = element.shadowRoot.querySelectorAll('article span.raa-diff-added, article span.raa-diff-removed, article span.raa-diff-changed');
        expect(badges).toHaveLength(3);
    });

    it('shows an error message when the Apex call fails', async () => {
        getAnalysisDiff.mockRejectedValue({ body: { message: 'Comparison unavailable.' } });
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Comparison unavailable.');
    });

    it('dispatches a close event when the close button is clicked', async () => {
        getAnalysisDiff.mockResolvedValue(null);
        const element = createComponent();
        await flushPromises();

        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);
        element.shadowRoot.querySelector('footer button').click();

        expect(closeHandler).toHaveBeenCalled();
    });
});
