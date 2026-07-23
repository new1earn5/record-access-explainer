import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasRunPermission from '@salesforce/apex/RAA_RecordAccessExplainerController.hasRunPermission';
import getDefaultSettings from '@salesforce/apex/RAA_RecordAccessExplainerController.getDefaultSettings';
import startAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.startAnalysis';
import getAnalysisStatus from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisStatus';
import getResults from '@salesforce/apex/RAA_RecordAccessExplainerController.getResults';
import cancelAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.cancelAnalysis';
import deleteAnalysis from '@salesforce/apex/RAA_RecordAccessExplainerController.deleteAnalysis';
import exportResultsCsv from '@salesforce/apex/RAA_RecordAccessExplainerController.exportResultsCsv';
import exportReasonsCsv from '@salesforce/apex/RAA_RecordAccessExplainerController.exportReasonsCsv';

const POLL_INTERVAL_MS = 3000;
const TERMINAL_STATUSES = ['Completed', 'Completed with Warnings', 'Failed', 'Cancelled'];
const PAGE_SIZE = 10;

const COLUMNS = [
    { label: 'User', fieldName: 'userFullName', type: 'text', sortable: true },
    { label: 'Username', fieldName: 'username', type: 'text', sortable: true },
    { label: 'Active', fieldName: 'isActive', type: 'boolean', sortable: true },
    { label: 'User Type', fieldName: 'userType', type: 'text', sortable: true },
    { label: 'Profile', fieldName: 'profileName', type: 'text', sortable: true },
    { label: 'Max Access', fieldName: 'maxAccessLevel', type: 'text', sortable: true },
    { label: 'Read', fieldName: 'hasReadAccess', type: 'boolean', sortable: true },
    { label: 'Edit', fieldName: 'hasEditAccess', type: 'boolean', sortable: true },
    { label: 'Delete', fieldName: 'hasDeleteAccess', type: 'boolean', sortable: true },
    { label: 'Transfer', fieldName: 'hasTransferAccess', type: 'boolean', sortable: true },
    { label: 'All Access', fieldName: 'hasAllAccess', type: 'boolean', sortable: true },
    { label: 'Reason Summary', fieldName: 'reasonSummary', type: 'text', wrapText: true },
    { label: 'Confidence', fieldName: 'overallConfidence', type: 'text', sortable: true },
    {
        type: 'button',
        typeAttributes: { label: 'View Reasons', name: 'view_reasons', variant: 'brand-outline' },
        cellAttributes: { alignment: 'left' }
    }
];

export default class RaaRecordAccessExplainer extends LightningElement {
    // Scan input
    recordIdInput = '';
    includeExternalUsers = false;
    includeInactiveUsers = false;
    profileNamesInput = '';
    userTypesInput = '';
    validationMessage = '';

    // Permission / bootstrap
    hasPermission = true;
    permissionChecked = false;

    // Analysis state
    analysisId;
    summary;
    results = [];
    isLoading = false;
    isStarting = false;
    genericErrorMessage = '';

    // Results filters
    searchTerm = '';
    accessLevelFilter = '';
    categoryFilter = '';
    profileFilter = '';
    userTypeFilter = '';
    activeFilter = '';
    confidenceFilter = '';
    unresolvedOnly = false;

    // Sorting / paging
    sortBy = 'userFullName';
    sortDirection = 'asc';
    currentPage = 1;

    // Detail modal
    selectedResult;

    pollingHandle;
    columns = COLUMNS;

    connectedCallback() {
        hasRunPermission()
            .then((result) => {
                this.hasPermission = result;
                this.permissionChecked = true;
            })
            .catch(() => {
                this.hasPermission = false;
                this.permissionChecked = true;
            });

        getDefaultSettings()
            .then((settings) => {
                this.includeExternalUsers = settings.defaultIncludeExternalUsers;
                this.includeInactiveUsers = settings.defaultIncludeInactiveUsers;
            })
            .catch(() => {
                // Defaults simply stay at their initial values if this call is not permitted.
            });
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // ---- Getters for template ----

    get showUnauthorized() {
        return this.permissionChecked && !this.hasPermission;
    }

    get showScanForm() {
        return this.permissionChecked && this.hasPermission && !this.analysisId;
    }

    get showProgress() {
        return !!this.analysisId && this.summary && !this.isTerminal;
    }

    get showResults() {
        return !!this.analysisId && this.summary && this.isTerminal;
    }

    get isTerminal() {
        return this.summary && TERMINAL_STATUSES.includes(this.summary.status);
    }

    get progressPercent() {
        if (!this.summary || !this.summary.totalUsers) {
            return 0;
        }
        return Math.min(100, Math.round((this.summary.processedUsers / this.summary.totalUsers) * 100));
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get statusExplanation() {
        const explanations = {
            Queued: 'The scan has been accepted and is waiting for a batch execution slot.',
            Running: 'The scan is actively evaluating the user population in the background.',
            Completed: 'The scan finished with no warnings.',
            'Completed with Warnings': 'The scan finished, but some access reasons could not be fully resolved, or a platform limitation was hit. See the warning banner below.',
            Failed: 'The scan could not complete. See the error details below.',
            Cancelled: 'The scan was cancelled before it finished.'
        };
        return this.summary ? explanations[this.summary.status] || '' : '';
    }

    get showWarningBanner() {
        return this.summary && (this.summary.potentiallyIncomplete || this.summary.status === 'Failed');
    }

    get warningText() {
        if (!this.summary) {
            return '';
        }
        return this.summary.status === 'Failed' ? this.summary.errorDetails : this.summary.warnings;
    }

    get canCancel() {
        return this.summary && !this.isTerminal;
    }

    get cancelDisabled() {
        return !this.canCancel;
    }

    get activeFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Active only', value: 'active' },
            { label: 'Inactive only', value: 'inactive' }
        ];
    }

    get confidenceFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' },
            { label: 'Mixed', value: 'Mixed' }
        ];
    }

    get filteredResults() {
        let rows = [...this.results];
        const term = this.searchTerm.trim().toLowerCase();

        if (term) {
            rows = rows.filter(
                (r) => (r.userFullName || '').toLowerCase().includes(term) || (r.username || '').toLowerCase().includes(term)
            );
        }
        if (this.accessLevelFilter) {
            rows = rows.filter((r) => r.maxAccessLevel === this.accessLevelFilter);
        }
        if (this.categoryFilter) {
            rows = rows.filter((r) => (r.reasons || []).some((reason) => reason.category === this.categoryFilter));
        }
        if (this.profileFilter) {
            rows = rows.filter((r) => r.profileName === this.profileFilter);
        }
        if (this.userTypeFilter) {
            rows = rows.filter((r) => r.userType === this.userTypeFilter);
        }
        if (this.activeFilter === 'active') {
            rows = rows.filter((r) => r.isActive);
        } else if (this.activeFilter === 'inactive') {
            rows = rows.filter((r) => !r.isActive);
        }
        if (this.confidenceFilter) {
            rows = rows.filter((r) => r.overallConfidence === this.confidenceFilter);
        }
        if (this.unresolvedOnly) {
            rows = rows.filter((r) => r.hasUnresolvedReason);
        }

        rows.sort((a, b) => {
            const valueA = a[this.sortBy];
            const valueB = b[this.sortBy];
            let result = 0;
            if (valueA > valueB) {
                result = 1;
            } else if (valueA < valueB) {
                result = -1;
            }
            return this.sortDirection === 'asc' ? result : -result;
        });

        return rows;
    }

    get totalRecords() {
        return this.filteredResults.length;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / PAGE_SIZE));
    }

    get pagedResults() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredResults.slice(start, start + PAGE_SIZE);
    }

    get paginationSummary() {
        if (this.totalRecords === 0) {
            return 'No matching users';
        }
        const start = (this.currentPage - 1) * PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * PAGE_SIZE, this.totalRecords);
        return `Showing ${start}-${end} of ${this.totalRecords} users with access`;
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get hasNoResults() {
        return this.isTerminal && this.results.length === 0;
    }

    get hasNoFilteredResults() {
        return this.results.length > 0 && this.filteredResults.length === 0;
    }

    get accessLevelOptions() {
        return this.buildPicklistOptions((r) => r.maxAccessLevel);
    }

    get profileOptions() {
        return this.buildPicklistOptions((r) => r.profileName);
    }

    get userTypeOptions() {
        return this.buildPicklistOptions((r) => r.userType);
    }

    get categoryOptions() {
        const values = new Set();
        this.results.forEach((r) => (r.reasons || []).forEach((reason) => reason.category && values.add(reason.category)));
        return [{ label: 'All Categories', value: '' }, ...[...values].sort().map((v) => ({ label: v, value: v }))];
    }

    buildPicklistOptions(accessor) {
        const values = new Set();
        this.results.forEach((r) => {
            const v = accessor(r);
            if (v) {
                values.add(v);
            }
        });
        return [{ label: 'All', value: '' }, ...[...values].sort().map((v) => ({ label: v, value: v }))];
    }

    // ---- Event handlers: scan input ----

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

    handleProfileNamesChange(event) {
        this.profileNamesInput = event.target.value;
    }

    handleUserTypesChange(event) {
        this.userTypesInput = event.target.value;
    }

    handleAnalyze() {
        const trimmed = (this.recordIdInput || '').trim();
        if (!trimmed) {
            this.validationMessage = 'Please enter a record ID.';
            return;
        }
        if (!/^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(trimmed)) {
            this.validationMessage = 'That does not look like a valid 15 or 18 character Salesforce record ID.';
            return;
        }
        this.validationMessage = '';
        this.startScan(false);
    }

    startScan(confirmDuplicateScan) {
        this.isStarting = true;
        const request = {
            recordId: this.recordIdInput.trim(),
            includeExternalUsers: this.includeExternalUsers,
            includeInactiveUsers: this.includeInactiveUsers,
            profileNames: this.splitCsv(this.profileNamesInput),
            userTypes: this.splitCsv(this.userTypesInput),
            permissionSetNames: [],
            confirmDuplicateScan
        };

        startAnalysis({ request })
            .then((summary) => {
                this.analysisId = summary.analysisId;
                this.summary = summary;
                this.results = [];
                this.currentPage = 1;
                if (TERMINAL_STATUSES.includes(summary.status)) {
                    // A very small scan can already be terminal by the time startAnalysis
                    // returns - load results immediately instead of waiting for the first poll.
                    this.loadResults();
                } else {
                    this.startPolling();
                }
            })
            .catch((error) => {
                const message = this.reduceError(error);
                if (message.includes('already') && message.includes('Confirm')) {
                    // eslint-disable-next-line no-alert
                    if (confirm(message + '\n\nStart a new scan anyway?')) {
                        this.startScan(true);
                        return;
                    }
                }
                this.showError(message);
            })
            .finally(() => {
                this.isStarting = false;
            });
    }

    splitCsv(value) {
        return (value || '')
            .split(',')
            .map((v) => v.trim())
            .filter((v) => v.length > 0);
    }

    // ---- Polling ----

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
        if (!this.analysisId) {
            return;
        }
        getAnalysisStatus({ analysisId: this.analysisId })
            .then((summary) => {
                this.summary = summary;
                if (TERMINAL_STATUSES.includes(summary.status)) {
                    this.stopPolling();
                    this.loadResults();
                }
            })
            .catch((error) => {
                this.stopPolling();
                this.showError(this.reduceError(error));
            });
    }

    loadResults() {
        if (!this.analysisId) {
            return;
        }
        this.isLoading = true;
        getResults({ analysisId: this.analysisId })
            .then((results) => {
                this.results = results || [];
                this.currentPage = 1;
            })
            .catch((error) => {
                this.showError(this.reduceError(error));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ---- Result grid interactions ----

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view_reasons') {
            this.selectedResult = event.detail.row;
        }
    }

    handleCloseDetail() {
        this.selectedResult = undefined;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
    }

    handleAccessLevelFilterChange(event) {
        this.accessLevelFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleCategoryFilterChange(event) {
        this.categoryFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleProfileFilterChange(event) {
        this.profileFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleUserTypeFilterChange(event) {
        this.userTypeFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleActiveFilterChange(event) {
        this.activeFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleConfidenceFilterChange(event) {
        this.confidenceFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleUnresolvedOnlyChange(event) {
        this.unresolvedOnly = event.target.checked;
        this.currentPage = 1;
    }

    handlePreviousPage() {
        if (!this.isFirstPage) {
            this.currentPage -= 1;
        }
    }

    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage += 1;
        }
    }

    // ---- Actions ----

    handleCancelScan() {
        if (!this.analysisId) {
            return;
        }
        cancelAnalysis({ analysisId: this.analysisId })
            .then((summary) => {
                this.summary = summary;
                this.stopPolling();
                this.showToast('Success', 'The scan was cancelled.', 'success');
            })
            .catch((error) => this.showError(this.reduceError(error)));
    }

    handleDeleteAnalysis() {
        if (!this.analysisId) {
            return;
        }
        deleteAnalysis({ analysisId: this.analysisId })
            .then(() => {
                this.showToast('Success', 'The analysis was deleted.', 'success');
                this.handleNewAnalysis();
            })
            .catch((error) => this.showError(this.reduceError(error)));
    }

    handleRefresh() {
        this.refreshStatus();
        if (this.isTerminal) {
            this.loadResults();
        }
    }

    handleNewAnalysis() {
        this.stopPolling();
        this.analysisId = undefined;
        this.summary = undefined;
        this.results = [];
        this.recordIdInput = '';
        this.selectedResult = undefined;
        this.currentPage = 1;
    }

    handleExportResults() {
        this.downloadCsv(exportResultsCsv, `record-access-results-${this.analysisId}.csv`);
    }

    handleExportReasons() {
        this.downloadCsv(exportReasonsCsv, `record-access-reasons-${this.analysisId}.csv`);
    }

    downloadCsv(apexMethod, fileName) {
        apexMethod({ analysisId: this.analysisId })
            .then((csv) => {
                const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
                const url = URL.createObjectURL(blob);
                const link = document.createElement('a');
                link.href = url;
                link.download = fileName;
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                URL.revokeObjectURL(url);
            })
            .catch((error) => this.showError(this.reduceError(error)));
    }

    // ---- Utilities ----

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(message) {
        this.genericErrorMessage = message;
        this.showToast('Error', message, 'error');
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again or contact your administrator.';
    }
}
