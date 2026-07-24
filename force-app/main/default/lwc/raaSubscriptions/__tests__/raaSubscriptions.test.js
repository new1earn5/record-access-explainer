import { createElement } from 'lwc';
import RaaSubscriptions from 'c/raaSubscriptions';
import listMySubscriptions from '@salesforce/apex/RAA_RecordAccessExplainerController.listMySubscriptions';
import createSubscription from '@salesforce/apex/RAA_RecordAccessExplainerController.createSubscription';
import setSubscriptionActive from '@salesforce/apex/RAA_RecordAccessExplainerController.setSubscriptionActive';
import deleteSubscription from '@salesforce/apex/RAA_RecordAccessExplainerController.deleteSubscription';

jest.mock(
    '@salesforce/apex/RAA_RecordAccessExplainerController.listMySubscriptions',
    () => ({ default: jest.fn() }),
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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const SAMPLE_SUBSCRIPTION = {
    subscriptionId: 's00000000000001',
    recordDisplayName: 'Acme Corp',
    objectApiName: 'Account',
    isActive: true,
    notifyOnChange: true,
    postToChatter: false,
    lastRunAt: '2026-07-20T00:00:00.000Z'
};

function recordIdInput(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (el) => el.label === 'Record ID'
    );
}

function createButton(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
        (el) => el.label === 'Create Subscription'
    );
}

describe('c-raa-subscriptions', () => {
    afterEach(() => {
        jest.clearAllMocks();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        listMySubscriptions.mockResolvedValue([]);
        const element = createElement('c-raa-subscriptions', {
            is: RaaSubscriptions
        });
        document.body.appendChild(element);
        return element;
    }

    it('loads subscriptions on connect and shows the empty state', async () => {
        const element = createComponent();
        await flushPromises();

        expect(listMySubscriptions).toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain(
            'You have no subscriptions yet.'
        );
    });

    it('renders subscriptions in the datatable when present', async () => {
        listMySubscriptions.mockResolvedValue([SAMPLE_SUBSCRIPTION]);
        const element = createElement('c-raa-subscriptions', {
            is: RaaSubscriptions
        });
        document.body.appendChild(element);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
        expect(datatable.data).toHaveLength(1);
    });

    it('shows a validation message for an invalid record ID', async () => {
        const element = createComponent();
        await flushPromises();

        createButton(element).click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Enter a valid 15 or 18 character record ID'
        );
        expect(createSubscription).not.toHaveBeenCalled();
    });

    it('creates a subscription and reloads the list', async () => {
        createSubscription.mockResolvedValue('s00000000000001');
        const element = createComponent();
        await flushPromises();

        const input = recordIdInput(element);
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change'));

        listMySubscriptions.mockResolvedValue([SAMPLE_SUBSCRIPTION]);
        createButton(element).click();
        await flushPromises();

        expect(createSubscription).toHaveBeenCalledWith({
            recordId: '001000000000001AAA',
            includeExternalUsers: false,
            includeInactiveUsers: false,
            notifyOnChange: true,
            postToChatter: false
        });
        expect(listMySubscriptions).toHaveBeenCalledTimes(2);
    });

    it('includes postToChatter when the Chatter checkbox is checked', async () => {
        createSubscription.mockResolvedValue('s00000000000001');
        const element = createComponent();
        await flushPromises();

        const input = recordIdInput(element);
        input.value = '001000000000001AAA';
        input.dispatchEvent(new CustomEvent('change'));

        const chatterCheckbox = [
            ...element.shadowRoot.querySelectorAll('lightning-input')
        ].find((el) => el.label === 'Post to Chatter when access changes');
        chatterCheckbox.checked = true;
        chatterCheckbox.dispatchEvent(new CustomEvent('change'));

        createButton(element).click();
        await flushPromises();

        expect(createSubscription).toHaveBeenCalledWith(
            expect.objectContaining({ postToChatter: true })
        );
    });

    it('pauses a subscription via row action', async () => {
        listMySubscriptions.mockResolvedValue([SAMPLE_SUBSCRIPTION]);
        setSubscriptionActive.mockResolvedValue();
        const element = createElement('c-raa-subscriptions', {
            is: RaaSubscriptions
        });
        document.body.appendChild(element);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action: { name: 'pause' }, row: SAMPLE_SUBSCRIPTION }
            })
        );
        await flushPromises();

        expect(setSubscriptionActive).toHaveBeenCalledWith({
            subscriptionId: 's00000000000001',
            isActive: false
        });
    });

    it('deletes a subscription via row action', async () => {
        listMySubscriptions.mockResolvedValue([SAMPLE_SUBSCRIPTION]);
        deleteSubscription.mockResolvedValue();
        const element = createElement('c-raa-subscriptions', {
            is: RaaSubscriptions
        });
        document.body.appendChild(element);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        datatable.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { action: { name: 'delete' }, row: SAMPLE_SUBSCRIPTION }
            })
        );
        await flushPromises();

        expect(deleteSubscription).toHaveBeenCalledWith({
            subscriptionId: 's00000000000001'
        });
    });
});
