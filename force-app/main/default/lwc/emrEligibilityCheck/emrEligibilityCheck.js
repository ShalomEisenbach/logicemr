import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getChecks from '@salesforce/apex/EligibilityCheckController.getChecks';
import runCheck from '@salesforce/apex/EligibilityCheckController.runCheck';
import ELIGIBILITY_CHECK_OBJECT from '@salesforce/schema/Eligibility_Check__c';
import NAME_FIELD from '@salesforce/schema/Eligibility_Check__c.Name';
import STATUS_FIELD from '@salesforce/schema/Eligibility_Check__c.Status__c';
import PLAN_FIELD from '@salesforce/schema/Eligibility_Check__c.Plan_Name__c';
import COPAY_FIELD from '@salesforce/schema/Eligibility_Check__c.Copay__c';
import DEDUCTIBLE_FIELD from '@salesforce/schema/Eligibility_Check__c.Deductible__c';
import CHECKED_FIELD from '@salesforce/schema/Eligibility_Check__c.Checked_Date__c';
import ERROR_FIELD from '@salesforce/schema/Eligibility_Check__c.Error_Message__c';
import hasRunEligibility from '@salesforce/customPermission/LogicEMR_Run_Eligibility';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

export default class EmrEligibilityCheck extends NavigationMixin(LightningElement) {
    @api embedded = false;

    _recordId;
    latestCheck;
    priorChecks = [];
    errorMessage;
    isLoading = false;
    isChecking = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed) {
            this.latestCheck = undefined;
            this.errorMessage = undefined;
            if (value) {
                this.loadChecks();
            } else {
                this.priorChecks = [];
            }
        }
    }

    get checkObjectApiName() {
        return ELIGIBILITY_CHECK_OBJECT.objectApiName;
    }

    get canRunEligibility() {
        return hasRunEligibility;
    }

    get showCard() {
        return !this.embedded;
    }

    get rootClass() {
        return this.embedded ? 'slds-is-relative' : 'slds-card slds-is-relative';
    }

    get bodyClass() {
        return this.embedded
            ? 'slds-is-relative'
            : 'slds-card__body slds-card__body_inner slds-is-relative';
    }

    get isBusy() {
        return this.isLoading || this.isChecking;
    }

    get hasLatest() {
        return Boolean(this.latestCheck?.Id);
    }

    get hasPrior() {
        return this.priorChecks && this.priorChecks.length > 0;
    }

    get showEmptyPrior() {
        return !this.isLoading && !this.hasPrior && !this.errorMessage;
    }

    get latestStatus() {
        return this.latestCheck ? this.latestCheck[STATUS_FIELD.fieldApiName] : '';
    }

    get latestPlan() {
        return this.latestCheck ? this.latestCheck[PLAN_FIELD.fieldApiName] : '';
    }

    get latestCopay() {
        return this.latestCheck ? this.latestCheck[COPAY_FIELD.fieldApiName] : null;
    }

    get latestDeductible() {
        return this.latestCheck ? this.latestCheck[DEDUCTIBLE_FIELD.fieldApiName] : null;
    }

    get latestName() {
        return this.latestCheck ? this.latestCheck[NAME_FIELD.fieldApiName] : '';
    }

    get latestError() {
        return this.latestCheck ? this.latestCheck[ERROR_FIELD.fieldApiName] || '' : '';
    }

    get statusBadgeClass() {
        const status = (this.latestStatus || '').toLowerCase();
        if (status === 'active') {
            return 'slds-badge slds-theme_success';
        }
        if (status === 'inactive') {
            return 'slds-badge slds-theme_warning';
        }
        if (status === 'error') {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge';
    }

    get columns() {
        return [
            urlColumn('Check', 'recordUrl', 'recordLabel'),
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            { label: 'Plan', fieldName: PLAN_FIELD.fieldApiName, wrapText: true },
            {
                label: 'Copay',
                fieldName: COPAY_FIELD.fieldApiName,
                type: 'currency',
                typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
            },
            {
                label: 'Deductible',
                fieldName: DEDUCTIBLE_FIELD.fieldApiName,
                type: 'currency',
                typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
            },
            {
                label: 'Checked',
                fieldName: CHECKED_FIELD.fieldApiName,
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                }
            }
        ];
    }

    get priorCards() {
        return (this.priorChecks || []).map((row) => ({
            id: row.Id,
            title: row.recordLabel || row[NAME_FIELD.fieldApiName] || 'Eligibility check',
            meta: [row[STATUS_FIELD.fieldApiName], row[PLAN_FIELD.fieldApiName]].filter((part) => part).join(' · '),
            objectApiName: ELIGIBILITY_CHECK_OBJECT.objectApiName
        }));
    }

    async loadChecks() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const rows = await getChecks({ coverageId: this._recordId });
            this.priorChecks = await withRecordUrls(this, rows || [], ELIGIBILITY_CHECK_OBJECT.objectApiName, {
                labelField: NAME_FIELD.fieldApiName
            });
            if (!this.latestCheck && this.priorChecks.length) {
                this.latestCheck = this.priorChecks[0];
            }
        } catch (error) {
            this.priorChecks = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleCheckEligibility() {
        if (!this._recordId || this.isChecking || !this.canRunEligibility) {
            return;
        }
        this.isChecking = true;
        this.errorMessage = undefined;
        try {
            const stored = await runCheck({ coverageId: this._recordId });
            this.latestCheck = stored;
            await this.loadChecks();
            this.dispatchEvent(new CustomEvent('eligibilitychecked'));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isChecking = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to check eligibility.';
    }
}
