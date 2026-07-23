import { createElement } from 'lwc';
import RaaUserAccessExplorer from 'c/raaUserAccessExplorer';
import scanUserAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.scanUserAccess';
import getUserAccessReasons from '@salesforce/apex/RAA_RecordAccessExplainerController.getUserAccessReasons';

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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const VALID_USER_ID = '005000000000001AAA';

const SAMPLE_RESULTS = [
    {
        recordId: '001000000000001AAA',
        recordDisplayName: 'Acme Corp',
        hasAnyAccess: true,
        maxAccessLevel: 'Edit',
        hasReadAccess: true,
        hasEditAccess: true,
        hasDeleteAccess: false,
        hasTransferAccess: false,
        hasAllAccess: false
    }
];

describe('c-raa-user-access-explorer', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-raa-user-access-explorer', {
            is: RaaUserAccessExplorer
        });
        document.body.appendChild(element);
        return element;
    }

    it('shows a validation message for an invalid user ID', async () => {
        const element = createComponent();

        element.shadowRoot
            .querySelector('[data-id="user-scan-button"]')
            .click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Enter a valid 15 or 18 character User ID'
        );
        expect(scanUserAccess).not.toHaveBeenCalled();
    });

    it('shows a validation message when the object API name is blank', async () => {
        const element = createComponent();

        const userIdInput = element.shadowRoot.querySelector(
            '[data-id="user-id-input"]'
        );
        userIdInput.value = VALID_USER_ID;
        userIdInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot
            .querySelector('[data-id="user-scan-button"]')
            .click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Enter the object API name'
        );
        expect(scanUserAccess).not.toHaveBeenCalled();
    });

    it('scans with explicit record IDs when provided, ignoring the limit', async () => {
        scanUserAccess.mockResolvedValue(SAMPLE_RESULTS);
        const element = createComponent();

        const userIdInput = element.shadowRoot.querySelector(
            '[data-id="user-id-input"]'
        );
        userIdInput.value = VALID_USER_ID;
        userIdInput.dispatchEvent(new CustomEvent('change'));

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const objectInput = [...inputs].find(
            (el) => el.label === 'Object API Name'
        );
        objectInput.value = 'Account';
        objectInput.dispatchEvent(new CustomEvent('change'));

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = '001000000000001AAA,001000000000002AAA';
        textarea.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot
            .querySelector('[data-id="user-scan-button"]')
            .click();
        await flushPromises();

        expect(scanUserAccess).toHaveBeenCalledWith({
            userId: VALID_USER_ID,
            objectApiName: 'Account',
            recordIds: ['001000000000001AAA', '001000000000002AAA'],
            limitCount: null
        });

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable.data).toHaveLength(1);
    });

    it('falls back to the limit count when no record IDs are supplied', async () => {
        scanUserAccess.mockResolvedValue(SAMPLE_RESULTS);
        const element = createComponent();

        const userIdInput = element.shadowRoot.querySelector(
            '[data-id="user-id-input"]'
        );
        userIdInput.value = VALID_USER_ID;
        userIdInput.dispatchEvent(new CustomEvent('change'));

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const objectInput = [...inputs].find(
            (el) => el.label === 'Object API Name'
        );
        objectInput.value = 'Account';
        objectInput.dispatchEvent(new CustomEvent('change'));

        element.shadowRoot
            .querySelector('[data-id="user-scan-button"]')
            .click();
        await flushPromises();

        expect(scanUserAccess).toHaveBeenCalledWith({
            userId: VALID_USER_ID,
            objectApiName: 'Account',
            recordIds: null,
            limitCount: 50
        });
    });

    it('lazily loads reasons for a row and opens the reason detail modal', async () => {
        scanUserAccess.mockResolvedValue(SAMPLE_RESULTS);
        getUserAccessReasons.mockResolvedValue([
            {
                category: 'Ownership',
                accessLevel: 'Full Access',
                confidence: 'High',
                isDirect: true,
                grantPath: 'Owner -> User',
                explanation: 'Owns the record.'
            }
        ]);

        const element = createComponent();
        const userIdInput = element.shadowRoot.querySelector(
            '[data-id="user-id-input"]'
        );
        userIdInput.value = VALID_USER_ID;
        userIdInput.dispatchEvent(new CustomEvent('change'));
        const objectInput = [
            ...element.shadowRoot.querySelectorAll('lightning-input')
        ].find((el) => el.label === 'Object API Name');
        objectInput.value = 'Account';
        objectInput.dispatchEvent(new CustomEvent('change'));
        element.shadowRoot
            .querySelector('[data-id="user-scan-button"]')
            .click();
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: {
                    action: { name: 'view_reasons' },
                    row: SAMPLE_RESULTS[0]
                }
            })
        );
        await flushPromises();

        expect(getUserAccessReasons).toHaveBeenCalledWith({
            userId: VALID_USER_ID,
            recordId: '001000000000001AAA'
        });
        const detail = element.shadowRoot.querySelector('c-raa-reason-detail');
        expect(detail).not.toBeNull();
        expect(detail.reasons).toHaveLength(1);
    });
});
