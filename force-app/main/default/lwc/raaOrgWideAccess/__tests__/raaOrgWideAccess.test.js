import { createElement } from 'lwc';
import RaaOrgWideAccess from 'c/raaOrgWideAccess';
import scanOrgWideAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.scanOrgWideAccess';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.scanOrgWideAccess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createComponent() {
    const element = createElement('c-raa-org-wide-access', {
        is: RaaOrgWideAccess
    });
    document.body.appendChild(element);
    return element;
}

function objectNamesInput(element) {
    return element.shadowRoot.querySelector('[data-id="object-names-input"]');
}

function scanButton(element) {
    return element.shadowRoot.querySelector('[data-id="scan-button"]');
}

describe('c-raa-org-wide-access', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows a validation message when no object name is entered', async () => {
        const element = createComponent();
        scanButton(element).click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Enter at least one object API name.'
        );
        expect(scanOrgWideAccess).not.toHaveBeenCalled();
    });

    it('parses a comma-separated object list and calls Apex', async () => {
        scanOrgWideAccess.mockResolvedValue([]);
        const element = createComponent();

        const input = objectNamesInput(element);
        input.value = 'Account, Contact ,  Opportunity';
        input.dispatchEvent(new CustomEvent('change'));

        scanButton(element).click();
        await flushPromises();

        expect(scanOrgWideAccess).toHaveBeenCalledWith({
            objectApiNames: ['Account', 'Contact', 'Opportunity']
        });
    });

    it('shows the empty state when the scan returns no rows', async () => {
        scanOrgWideAccess.mockResolvedValue([]);
        const element = createComponent();

        const input = objectNamesInput(element);
        input.value = 'Account';
        input.dispatchEvent(new CustomEvent('change'));
        scanButton(element).click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'No Profile or Permission Set'
        );
    });

    it('renders results with a derived bypass type label', async () => {
        scanOrgWideAccess.mockResolvedValue([
            {
                principalName: 'System Administrator',
                principalType: 'Profile',
                objectApiName: 'Account',
                hasViewAllRecords: false,
                hasModifyAllRecords: true,
                hasFullObjectCrud: false,
                activeUserCount: 3
            },
            {
                principalName: 'RAA View All Access',
                principalType: 'Permission Set',
                objectApiName: 'Account',
                hasViewAllRecords: true,
                hasModifyAllRecords: false,
                hasFullObjectCrud: false,
                activeUserCount: 1
            }
        ]);
        const element = createComponent();

        const input = objectNamesInput(element);
        input.value = 'Account';
        input.dispatchEvent(new CustomEvent('change'));
        scanButton(element).click();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(2);
        expect(datatable.data[0].bypassType).toBe('Modify All Records');
        expect(datatable.data[1].bypassType).toBe('View All Records');
    });

    it('shows an error toast when the Apex call fails', async () => {
        scanOrgWideAccess.mockRejectedValue({
            body: { message: 'Scan at most 10 objects at a time.' }
        });
        const handler = jest.fn();
        const element = createComponent();
        element.addEventListener('lightning__showtoast', handler);

        const input = objectNamesInput(element);
        input.value = 'Account';
        input.dispatchEvent(new CustomEvent('change'));
        scanButton(element).click();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.message).toBe(
            'Scan at most 10 objects at a time.'
        );
    });
});
