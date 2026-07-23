import { LightningElement, api } from 'lwc';

/**
 * Renders every detected access reason for a single user in a modal dialog. Purely
 * presentational - all data is passed in from the parent, which owns the Apex calls.
 */
export default class RaaReasonDetail extends LightningElement {
    @api userName;
    @api username;
    @api reasons = [];

    get hasReasons() {
        return this.reasons && this.reasons.length > 0;
    }

    get decoratedReasons() {
        return (this.reasons || []).map((reason, index) => ({
            ...reason,
            key: reason.recordId || index,
            confidenceVariant: this.confidenceVariant(reason.confidence),
            directLabel: reason.isDirect ? 'Direct' : 'Indirect',
            hasEvidence: !!reason.evidence,
            pathSteps: this.buildPathSteps(reason.grantPath)
        }));
    }

    confidenceVariant(confidence) {
        if (confidence === 'High') {
            return 'success';
        }
        if (confidence === 'Medium') {
            return 'warning';
        }
        return 'error';
    }

    buildPathSteps(grantPath) {
        if (!grantPath) {
            return [];
        }
        return grantPath
            .split('->')
            .map((segment) => segment.trim())
            .filter((segment) => segment.length > 0)
            .map((segment, index) => ({ key: index, label: segment }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }
}
