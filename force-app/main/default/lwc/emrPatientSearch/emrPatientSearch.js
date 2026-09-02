import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchPatients from '@salesforce/apex/PatientSearchController.search';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';

const DEBOUNCE_MS = 300;
const OPEN_CHART = 'open_chart';

export default class EmrPatientSearch extends NavigationMixin(LightningElement) {
    @api eager;
    @api height;
    @api icon;
    @api label;
    @api scrollable;
    @api width;
    patients = [];
    errorMessage;
    hasSearched = false;
    debounceTimer;

    columns = [
        { label: 'Last', fieldName: LAST_NAME_FIELD.fieldApiName },
        { label: 'First', fieldName: FIRST_NAME_FIELD.fieldApiName },
        { label: 'MRN', fieldName: MRN_FIELD.fieldApiName },
        { label: 'DOB', fieldName: DOB_FIELD.fieldApiName, type: 'date-local' },
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Open chart', name: OPEN_CHART }]
            }
        }
    ];

    get hasResults() {
        return this.patients.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.hasResults && !this.errorMessage;
    }

    disconnectedCallback() {
        window.clearTimeout(this.debounceTimer);
    }

    handleSearchChange(event) {
        window.clearTimeout(this.debounceTimer);
        const searchTerm = event.target.value;
        this.debounceTimer = window.setTimeout(() => {
            this.runSearch(searchTerm);
        }, DEBOUNCE_MS);
    }

    async runSearch(searchTerm) {
        const trimmed = searchTerm ? searchTerm.trim() : '';
        if (!trimmed) {
            this.patients = [];
            this.errorMessage = undefined;
            this.hasSearched = false;
            return;
        }

        try {
            this.patients = await searchPatients({ searchTerm: trimmed });
            this.errorMessage = undefined;
        } catch (error) {
            this.patients = [];
            this.errorMessage = this.reduceError(error);
        }
        this.hasSearched = true;
    }

    handleRowAction(event) {
        if (event.detail.action.name !== OPEN_CHART) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.row.Id,
                objectApiName: PATIENT_OBJECT.objectApiName,
                actionName: 'view'
            }
        });
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to search patients.';
    }
}
