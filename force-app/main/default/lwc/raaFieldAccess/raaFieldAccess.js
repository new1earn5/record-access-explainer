import { LightningElement, api } from 'lwc';
import getFieldAccess from '@salesforce/apex/RAA_RecordAccessExplainerController.getFieldAccess';

const COLUMNS = [
    { label: 'Field', fieldName: 'fieldLabel', type: 'text', sortable: true },
    { label: 'API Name', fieldName: 'fieldApiName', type: 'text', sortable: true },
    { label: 'Readable', fieldName: 'readable', type: 'boolean' },
    { label: 'Editable', fieldName: 'editable', type: 'boolean' }
];

/**
 * Modal showing field-level security for one user against one object. Field-level security is
 * independent of record-level sharing: a user can have object/record access and still be denied
 * individual fields, or vice versa - this view is deliberately separate from the reason list.
 */
export default class RaaFieldAccess extends LightningElement {
    @api userName;
    @api userId;
    @api objectApiName;

    fields = [];
    isLoading = true;
    errorMessage = '';
    columns = COLUMNS;

    connectedCallback() {
        getFieldAccess({ userId: this.userId, objectApiName: this.objectApiName })
            .then((result) => {
                this.fields = result;
            })
            .catch((error) => {
                this.errorMessage = error && error.body && error.body.message ? error.body.message : 'Unable to load field access.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasFields() {
        return this.fields && this.fields.length > 0;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }
}
