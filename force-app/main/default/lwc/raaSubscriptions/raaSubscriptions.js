import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listMySubscriptions from '@salesforce/apex/RAA_RecordAccessExplainerController.listMySubscriptions';
import createSubscription from '@salesforce/apex/RAA_RecordAccessExplainerController.createSubscription';
import setSubscriptionActive from '@salesforce/apex/RAA_RecordAccessExplainerController.setSubscriptionActive';
import deleteSubscription from '@salesforce/apex/RAA_RecordAccessExplainerController.deleteSubscription';

const COLUMNS = [
    {
        label: 'Record',
        fieldName: 'recordDisplayName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Object',
        fieldName: 'objectApiName',
        type: 'text',
        sortable: true
    },
    { label: 'Active', fieldName: 'isActive', type: 'boolean', sortable: true },
    { label: 'Notify On Change', fieldName: 'notifyOnChange', type: 'boolean' },
    { label: 'Last Run', fieldName: 'lastRunAt', type: 'date', sortable: true },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Pause', name: 'pause' },
                { label: 'Resume', name: 'resume' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

/**
 * Standing "watch this record" subscriptions, processed by the optional RAA_RecurringScanScheduler.
 * Requires that an administrator has scheduled RAA_RecurringScanScheduler (see README) - creating
 * a subscription here only registers the request; nothing runs until that scheduler is active.
 */
export default class RaaSubscriptions extends LightningElement {
    subscriptions = [];
    isLoading = true;
    recordIdInput = '';
    includeExternalUsers = false;
    includeInactiveUsers = false;
    notifyOnChange = true;
    validationMessage = '';
    isSaving = false;
    columns = COLUMNS;

    connectedCallback() {
        this.loadSubscriptions();
    }

    get hasSubscriptions() {
        return this.subscriptions && this.subscriptions.length > 0;
    }

    loadSubscriptions() {
        this.isLoading = true;
        listMySubscriptions()
            .then((result) => {
                this.subscriptions = result;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRecordIdChange(event) {
        this.recordIdInput = event.target.value;
        this.validationMessage = '';
    }

    handleIncludeExternalChange(event) {
        this.includeExternalUsers = event.target.checked;
    }

    handleIncludeInactiveChange(event) {
        this.includeInactiveUsers = event.target.checked;
    }

    handleNotifyOnChangeChange(event) {
        this.notifyOnChange = event.target.checked;
    }

    handleCreate() {
        const recordId = (this.recordIdInput || '').trim();
        if (!/^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(recordId)) {
            this.validationMessage =
                'Enter a valid 15 or 18 character record ID.';
            return;
        }
        this.validationMessage = '';
        this.isSaving = true;
        createSubscription({
            recordId,
            includeExternalUsers: this.includeExternalUsers,
            includeInactiveUsers: this.includeInactiveUsers,
            notifyOnChange: this.notifyOnChange
        })
            .then(() => {
                this.recordIdInput = '';
                this.showToast('Success', 'Subscription created.', 'success');
                this.loadSubscriptions();
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'pause') {
            this.toggleActive(row.subscriptionId, false);
        } else if (actionName === 'resume') {
            this.toggleActive(row.subscriptionId, true);
        } else if (actionName === 'delete') {
            this.remove(row.subscriptionId);
        }
    }

    toggleActive(subscriptionId, isActive) {
        setSubscriptionActive({ subscriptionId, isActive })
            .then(() => this.loadSubscriptions())
            .catch((error) => this.showError(error));
    }

    remove(subscriptionId) {
        deleteSubscription({ subscriptionId })
            .then(() => {
                this.showToast('Success', 'Subscription deleted.', 'success');
                this.loadSubscriptions();
            })
            .catch((error) => this.showError(error));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message =
            error && error.body && error.body.message
                ? error.body.message
                : 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}
