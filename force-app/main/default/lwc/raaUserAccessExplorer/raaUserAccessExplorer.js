import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import scanUserAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.scanUserAccess';
import getUserAccessReasons from '@salesforce/apex/RAA_RecordAccessExplainerController.getUserAccessReasons';

const COLUMNS = [
    { label: 'Record', fieldName: 'recordDisplayName', type: 'text', sortable: true },
    { label: 'Has Access', fieldName: 'hasAnyAccess', type: 'boolean', sortable: true },
    { label: 'Max Access', fieldName: 'maxAccessLevel', type: 'text', sortable: true },
    { label: 'Read', fieldName: 'hasReadAccess', type: 'boolean' },
    { label: 'Edit', fieldName: 'hasEditAccess', type: 'boolean' },
    { label: 'Delete', fieldName: 'hasDeleteAccess', type: 'boolean' },
    { label: 'Transfer', fieldName: 'hasTransferAccess', type: 'boolean' },
    { label: 'All Access', fieldName: 'hasAllAccess', type: 'boolean' },
    {
        type: 'button',
        typeAttributes: { label: 'View Reasons', name: 'view_reasons', variant: 'brand-outline' }
    }
];

/**
 * "By user" reverse-mode scan: given one user and a candidate set of records of the same
 * object, reports effective access to each. Reasons for a specific record are fetched lazily
 * when the admin clicks into a row, to keep the initial scan fast and governor-safe even for a
 * few hundred candidate records (see RAA_UserAccessExplorerService for why).
 */
export default class RaaUserAccessExplorer extends LightningElement {
    userIdInput = '';
    objectApiNameInput = '';
    recordIdsInput = '';
    limitInput = 50;
    validationMessage = '';
    isScanning = false;
    results;
    columns = COLUMNS;

    selectedReasons;
    selectedRecordName;
    isLoadingReasons = false;

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get showReasonModal() {
        return !!this.selectedReasons;
    }

    handleUserIdChange(event) {
        this.userIdInput = event.target.value;
        this.validationMessage = '';
    }

    handleObjectApiNameChange(event) {
        this.objectApiNameInput = event.target.value;
    }

    handleRecordIdsChange(event) {
        this.recordIdsInput = event.target.value;
    }

    handleLimitChange(event) {
        this.limitInput = event.target.value;
    }

    handleScan() {
        const userId = (this.userIdInput || '').trim();
        const objectApiName = (this.objectApiNameInput || '').trim();
        if (!/^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(userId)) {
            this.validationMessage = 'Enter a valid 15 or 18 character User ID.';
            return;
        }
        if (!objectApiName) {
            this.validationMessage = 'Enter the object API name to check (for example Account).';
            return;
        }
        this.validationMessage = '';

        const recordIds = (this.recordIdsInput || '')
            .split(/[\n,]/)
            .map((value) => value.trim())
            .filter((value) => value.length > 0);

        this.isScanning = true;
        scanUserAccess({
            userId,
            objectApiName,
            recordIds: recordIds.length > 0 ? recordIds : null,
            limitCount: recordIds.length > 0 ? null : Number(this.limitInput) || 50
        })
            .then((result) => {
                this.results = result;
            })
            .catch((error) => {
                this.showError(error);
            })
            .finally(() => {
                this.isScanning = false;
            });
    }

    handleRowAction(event) {
        if (event.detail.action.name !== 'view_reasons') {
            return;
        }
        const row = event.detail.row;
        this.isLoadingReasons = true;
        this.selectedRecordName = row.recordDisplayName;
        getUserAccessReasons({ userId: this.userIdInput.trim(), recordId: row.recordId })
            .then((reasons) => {
                this.selectedReasons = reasons;
            })
            .catch((error) => {
                this.showError(error);
            })
            .finally(() => {
                this.isLoadingReasons = false;
            });
    }

    handleCloseReasonModal() {
        this.selectedReasons = undefined;
        this.selectedRecordName = undefined;
    }

    showError(error) {
        const message = error && error.body && error.body.message ? error.body.message : 'An unexpected error occurred.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
