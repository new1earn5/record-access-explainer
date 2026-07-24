import { createElement } from 'lwc';
import RaaPlainEnglishSummary from 'c/raaPlainEnglishSummary';
import getPlainEnglishSummary from '@salesforce/apex/RAA_RecordAccessExplainerController.getPlainEnglishSummary';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getPlainEnglishSummary',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-raa-plain-english-summary', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-plain-english-summary', {
            is: RaaPlainEnglishSummary
        });
        element.analysisId = 'a00000000000001';
        element.recordDisplayName = 'Acme Corp';
        document.body.appendChild(element);
        return element;
    }

    it('loads and renders the summary text on connect', async () => {
        getPlainEnglishSummary.mockResolvedValue(
            '3 users have access to Acme Corp (Account).'
        );
        const element = createComponent();
        await flushPromises();

        expect(getPlainEnglishSummary).toHaveBeenCalledWith({
            analysisId: 'a00000000000001'
        });
        expect(element.shadowRoot.textContent).toContain(
            '3 users have access to Acme Corp'
        );
        expect(element.shadowRoot.textContent).toContain('Acme Corp');
    });

    it('shows an error message when the Apex call fails', async () => {
        getPlainEnglishSummary.mockRejectedValue({
            body: { message: 'This analysis has not finished yet.' }
        });
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'This analysis has not finished yet.'
        );
    });

    it('dispatches a close event when the close button is clicked', async () => {
        getPlainEnglishSummary.mockResolvedValue('1 user has access.');
        const element = createComponent();
        await flushPromises();

        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);
        element.shadowRoot.querySelector('footer button').click();

        expect(closeHandler).toHaveBeenCalled();
    });
});
