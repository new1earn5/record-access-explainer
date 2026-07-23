import { createElement } from 'lwc';
import RaaFieldAccess from 'c/raaFieldAccess';
import getFieldAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.getFieldAccess';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.getFieldAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-raa-field-access', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-field-access', {
            is: RaaFieldAccess
        });
        element.userName = 'Jane Doe';
        element.userId = '005000000000001AAA';
        element.objectApiName = 'Account';
        document.body.appendChild(element);
        return element;
    }

    it('loads field access on connect and renders the datatable', async () => {
        getFieldAccess.mockResolvedValue([
            {
                fieldApiName: 'Name',
                fieldLabel: 'Account Name',
                readable: true,
                editable: true
            },
            {
                fieldApiName: 'Website',
                fieldLabel: 'Website',
                readable: true,
                editable: false
            }
        ]);

        const element = createComponent();
        await flushPromises();

        expect(getFieldAccess).toHaveBeenCalledWith({
            userId: '005000000000001AAA',
            objectApiName: 'Account'
        });
        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(2);
        expect(element.shadowRoot.textContent).toContain('Jane Doe');
    });

    it('shows an error message when the Apex call fails', async () => {
        getFieldAccess.mockRejectedValue({
            body: { message: 'No access to field data.' }
        });

        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'No access to field data.'
        );
        expect(
            element.shadowRoot.querySelector('lightning-datatable')
        ).toBeNull();
    });

    it('dispatches a close event when the close button is clicked', async () => {
        getFieldAccess.mockResolvedValue([]);
        const element = createComponent();
        await flushPromises();

        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);

        const footerButton = element.shadowRoot.querySelector('footer button');
        footerButton.click();

        expect(closeHandler).toHaveBeenCalled();
    });
});
