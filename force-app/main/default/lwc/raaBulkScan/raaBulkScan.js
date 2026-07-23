import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startBulkAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.startBulkAnalysis';
import getBatchRunStatus from '@salesforce/apex/RAA_RecordAccessExplainerController.getBatchRunStatus';

const POLL_INTERVAL_MS = 4000;
const TERMINAL_STATUSES = ['Completed', 'Completed with Warnings', 'Failed', 'Cancelled'];

const COLUMNS = [
    { label: 'Record', fieldName: 'recordDisplayName', type: 'text', sortable: true },
    { label: 'Status', fieldName: 'status', type: 'text', sortable: true },
    { label: 'Users With Access', fieldName: 'usersWithAccess', type: 'number', sortable: true },
    {
        type: 'button',
        typeAttributes: { label: 'View Details', name: 'view_analysis', variant: 'brand-outline' }
    }
];

/**
 * Bulk scan mode: analyze every record in a pasted list in one submission. Each record reuses
 * the exact same single-record scan pipeline (RAA_AccessScanBatch); this component only
 * orchestrates submitting the list and polling the aggregate RAA_Batch_Run__c status.
 */
export default class RaaBulkScan extends LightningElement {
    recordIdsInput = '';
    includeExternalUsers = false;
    includeInactiveUsers = false;
    isStarting = false;
    validationMessage = '';
    batchRun;
    columns = COLUMNS;
    pollingHandle;

    disconnectedCallback() {
        this.stopPolling();
    }

    get showForm() {
        return !this.batchRun;
    }

    get showResults() {
        return !!this.batchRun;
    }

    get isTerminal() {
        return this.batchRun && TERMINAL_STATUSES.includes(this.batchRun.status);
    }

    get progressPercent() {
        if (!this.batchRun || !this.batchRun.totalRecords) {
            return 0;
        }
        return Math.min(100, Math.round((this.batchRun.completedRecords / this.batchRun.totalRecords) * 100));
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    handleRecordIdsChange(event) {
        this.recordIdsInput = event.target.value;
        this.validationMessage = '';
    }

    handleIncludeExternalChange(event) {
        this.includeExternalUsers = event.target.checked;
    }

    handleIncludeInactiveChange(event) {
        this.includeInactiveUsers = event.target.checked;
    }

    handleStart() {
        const ids = this.parseRecordIds(this.recordIdsInput);
        if (ids.length === 0) {
            this.validationMessage = 'Enter at least one record ID, one per line or separated by commas.';
            return;
        }

        this.isStarting = true;
        startBulkAnalysis({ recordIds: ids, includeExternalUsers: this.includeExternalUsers, includeInactiveUsers: this.includeInactiveUsers })
            .then((result) => {
                this.batchRun = result;
                this.startPolling();
            })
            .catch((error) => {
                this.showError(error);
            })
            .finally(() => {
                this.isStarting = false;
            });
    }

    parseRecordIds(raw) {
        return (raw || '')
            .split(/[\n,]/)
            .map((value) => value.trim())
            .filter((value) => value.length > 0);
    }

    startPolling() {
        this.stopPolling();
        this.pollingHandle = setInterval(() => this.refreshStatus(), POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollingHandle) {
            clearInterval(this.pollingHandle);
            this.pollingHandle = undefined;
        }
    }

    refreshStatus() {
        if (!this.batchRun) {
            return;
        }
        getBatchRunStatus({ batchRunId: this.batchRun.batchRunId })
            .then((result) => {
                this.batchRun = result;
                if (TERMINAL_STATUSES.includes(result.status)) {
                    this.stopPolling();
                }
            })
            .catch((error) => {
                this.stopPolling();
                this.showError(error);
            });
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view_analysis') {
            this.dispatchEvent(new CustomEvent('viewanalysis', { detail: { analysisId: event.detail.row.analysisId } }));
        }
    }

    handleNewBulkScan() {
        this.stopPolling();
        this.batchRun = undefined;
        this.recordIdsInput = '';
    }

    showError(error) {
        const message = error && error.body && error.body.message ? error.body.message : 'An unexpected error occurred.';
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}
