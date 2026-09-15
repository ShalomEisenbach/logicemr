import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getPatientSuperbills from '@salesforce/apex/PatientClaimsController.getPatientSuperbills';
import SUPERBILL_OBJECT from '@salesforce/schema/Superbill__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const COLUMNS = [
    urlColumn('Superbill', 'recordUrl', 'recordLabel'),
    {
        label: 'Date of Service',
        fieldName: 'dateOfService',
        type: 'date-local',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    },
    { label: 'Status', fieldName: 'status' },
    urlColumn('Encounter', 'encounterUrl', 'encounterLabel'),
    { label: 'Rendering Provider', fieldName: 'renderingPractitionerName', wrapText: true },
    { label: 'Payer', fieldName: 'payerName', wrapText: true },
    { label: 'Total', fieldName: 'totalCharges', type: 'currency' },
    { label: 'Readiness Issues', fieldName: 'validationMessages', wrapText: true }
];

export default class EmrPatientClaims extends NavigationMixin(LightningElement) {
    @api recordId;

    claims;
    errorMessage;
    isLoading = true;
    wiredClaimsResult;
    refreshHandlerId;

    columns = COLUMNS;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        return this.wiredClaimsResult ? refreshApex(this.wiredClaimsResult) : Promise.resolve();
    }

    @wire(getPatientSuperbills, { patientId: '$recordId' })
    wiredClaims(result) {
        this.wiredClaimsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyClaims(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.claims = [];
            this.errorMessage = this.reduceError(error);
            this.isLoading = false;
        }
    }

    async applyClaims(data) {
        const withClaimUrls = await withRecordUrls(this, data, SUPERBILL_OBJECT.objectApiName, {
            idField: 'id',
            labelField: 'name'
        });
        this.claims = await withRecordUrls(this, withClaimUrls, ENCOUNTER_OBJECT.objectApiName, {
            idField: 'encounterId',
            urlField: 'encounterUrl',
            labelField: 'encounterName',
            labelOutField: 'encounterLabel'
        });
        this.isLoading = false;
    }

    get superbillObjectApiName() {
        return SUPERBILL_OBJECT.objectApiName;
    }

    get encounterObjectApiName() {
        return ENCOUNTER_OBJECT.objectApiName;
    }

    get hasClaims() {
        return this.claims && this.claims.length > 0;
    }

    get showEmpty() {
        return this.claims && this.claims.length === 0 && !this.errorMessage;
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.refreshHandler();
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load patient claims.';
    }
}
