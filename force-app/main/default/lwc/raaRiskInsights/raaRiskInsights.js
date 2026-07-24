import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRiskInsights from '@salesforce/apex/RAA_RecordAccessExplainerController.getRiskInsights';

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
    {
        label: 'Risk Score',
        fieldName: 'riskScore',
        type: 'number',
        sortable: true,
        initialWidth: 110
    },
    {
        label: 'External Users',
        fieldName: 'externalUserCount',
        type: 'number',
        sortable: true
    },
    {
        label: 'Bypass Holders',
        fieldName: 'bypassHolderCount',
        type: 'number',
        sortable: true
    },
    {
        label: 'Unresolved',
        fieldName: 'unresolvedCount',
        type: 'number',
        sortable: true
    },
    {
        label: 'Users With Access',
        fieldName: 'usersWithAccess',
        type: 'number',
        sortable: true
    },
    {
        label: 'Last Scanned',
        fieldName: 'completedAt',
        type: 'date',
        sortable: true
    },
    {
        type: 'button',
        typeAttributes: {
            label: 'View Analysis',
            name: 'view_analysis',
            variant: 'brand-outline'
        }
    }
];

/**
 * Ranks records the current user has already scanned by risk signals already present in that
 * scan's own results - nothing here triggers a new scan. See RAA_RiskInsightsService for exactly
 * how riskScore is computed from the three columns shown alongside it.
 */
export default class RaaRiskInsights extends LightningElement {
    insights = [];
    isLoading = true;
    columns = COLUMNS;

    connectedCallback() {
        this.loadInsights();
    }

    get hasInsights() {
        return this.insights && this.insights.length > 0;
    }

    loadInsights() {
        this.isLoading = true;
        getRiskInsights()
            .then((result) => {
                this.insights = result;
            })
            .catch((error) => this.showError(error))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRefresh() {
        this.loadInsights();
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'view_analysis') {
            this.dispatchEvent(
                new CustomEvent('viewanalysis', {
                    detail: { analysisId: event.detail.row.analysisId }
                })
            );
        }
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
