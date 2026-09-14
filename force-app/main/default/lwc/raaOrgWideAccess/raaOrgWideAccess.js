import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import scanOrgWideAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.scanOrgWideAccess';

const COLUMNS = [
    {
        label: 'Object',
        fieldName: 'objectApiName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Principal',
        fieldName: 'principalName',
        type: 'text',
        sortable: true
    },
    {
        label: 'Type',
        fieldName: 'principalType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Bypass Type',
        fieldName: 'bypassType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Active Users',
        fieldName: 'activeUserCount',
        type: 'number',
        sortable: true
    }
];

/**
 * Standalone org-wide oversharing scan: independent of the record-scan pipeline, this asks
 * "which Profiles/Permission Sets currently grant broad access to these objects, and who
 * actually holds that access right now" - a starting point for exposure, not tied to any one
 * record. See RAA_OrgWideAccessService for exactly how bypassType/activeUserCount are computed.
 */
export default class RaaOrgWideAccess extends LightningElement {
    objectNamesInput = '';
    validationMessage = '';
    isScanning = false;
    hasScanned = false;
    results = [];
    columns = COLUMNS;

    get showResults() {
        return this.hasScanned && this.results.length > 0;
    }

    get showEmptyState() {
        return this.hasScanned && !this.isScanning && this.results.length === 0;
    }

    handleObjectNamesChange(event) {
        this.objectNamesInput = event.target.value;
        this.validationMessage = '';
    }

    handleScan() {
        const objectApiNames = (this.objectNamesInput || '')
            .split(',')
            .map((name) => name.trim())
            .filter((name) => name.length > 0);

        if (objectApiNames.length === 0) {
            this.validationMessage = 'Enter at least one object API name.';
            return;
        }

        this.validationMessage = '';
        this.isScanning = true;
        this.hasScanned = false;
        scanOrgWideAccess({ objectApiNames })
            .then((result) => {
                this.results = result.map((row, index) => ({
                    ...row,
                    rowKey:
                        index +
                        ':' +
                        row.principalType +
                        ':' +
                        row.principalName +
                        ':' +
                        row.objectApiName,
                    bypassType: this.describeBypassType(row)
                }));
                this.hasScanned = true;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isScanning = false;
            });
    }

    describeBypassType(row) {
        if (row.hasModifyAllRecords) {
            return 'Modify All Records';
        }
        if (row.hasViewAllRecords) {
            return 'View All Records';
        }
        return 'Full Object CRUD';
    }

    showError(error) {
        const message =
            error && error.body && error.body.message
                ? error.body.message
                : 'An unexpected error occurred.';
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Error', message, variant: 'error' })
        );
    }
}
