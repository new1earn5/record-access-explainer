import { LightningElement, api } from 'lwc';
import getAnalysisDiff from '@salesforce/apex/RAA_RecordAccessExplainerController.getAnalysisDiff';

/**
 * Modal showing what changed between this analysis and the most recent earlier completed
 * analysis of the same record: users who gained access, lost access, or had their effective
 * access level or reasons change.
 */
export default class RaaAnalysisDiff extends LightningElement {
    @api analysisId;
    @api recordDisplayName;

    diff;
    isLoading = true;
    errorMessage = '';
    noPreviousAnalysis = false;

    connectedCallback() {
        getAnalysisDiff({ analysisId: this.analysisId })
            .then((result) => {
                if (!result) {
                    this.noPreviousAnalysis = true;
                    return;
                }
                this.diff = {
                    ...result,
                    changes: (result.changes || []).map((change, index) => ({
                        ...change,
                        key: index,
                        badgeClass: this.badgeClass(change.changeType)
                    }))
                };
            })
            .catch((error) => {
                this.errorMessage =
                    error && error.body && error.body.message
                        ? error.body.message
                        : 'Unable to load comparison.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    badgeClass(changeType) {
        if (changeType === 'Added') {
            return 'raa-diff-added';
        }
        if (changeType === 'Removed') {
            return 'raa-diff-removed';
        }
        return 'raa-diff-changed';
    }

    get hasChanges() {
        return this.diff && this.diff.changes && this.diff.changes.length > 0;
    }

    get hasNoChanges() {
        return (
            this.diff && (!this.diff.changes || this.diff.changes.length === 0)
        );
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }
}
