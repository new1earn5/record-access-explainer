import { LightningElement, api } from 'lwc';
import getPlainEnglishSummary from '@salesforce/apex/RAA_RecordAccessExplainerController.getPlainEnglishSummary';

/**
 * Modal showing a completed scan's results as a short plain-English paragraph, deterministically
 * generated from the same structured data the results grid shows (see
 * RAA_PlainEnglishSummaryService) - not a generative-AI call.
 */
export default class RaaPlainEnglishSummary extends LightningElement {
    @api analysisId;
    @api recordDisplayName;

    summary;
    isLoading = true;
    errorMessage = '';

    connectedCallback() {
        getPlainEnglishSummary({ analysisId: this.analysisId })
            .then((result) => {
                this.summary = result;
            })
            .catch((error) => {
                this.errorMessage =
                    error && error.body && error.body.message
                        ? error.body.message
                        : 'Unable to load summary.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }
}
