import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchPatients from '@salesforce/apex/PatientSearchController.search';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import PHONE_FIELD from '@salesforce/schema/Patient__c.Phone__c';
import EMAIL_FIELD from '@salesforce/schema/Patient__c.Email__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const DEBOUNCE_MS = 300;
const OPEN_CHART = 'open_chart';

function formatDob(value) {
    if (!value) {
        return '';
    }
    const parsed = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(parsed.getTime())) {
        return String(value);
    }
    return parsed.toLocaleDateString();
}

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

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get columns() {
        return [
            urlColumn('Last', 'recordUrl', 'recordLabel'),
            { label: 'First', fieldName: FIRST_NAME_FIELD.fieldApiName },
            { label: 'MRN', fieldName: MRN_FIELD.fieldApiName },
            { label: 'DOB', fieldName: DOB_FIELD.fieldApiName, type: 'date-local' },
            { label: 'Phone', fieldName: PHONE_FIELD.fieldApiName, type: 'phone' },
            { label: 'Email', fieldName: EMAIL_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Open chart', name: OPEN_CHART }]
                }
            }
        ];
    }

    get hasResults() {
        return this.patients.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.hasResults && !this.errorMessage;
    }

    get patientCards() {
        return (this.patients || []).map((row) => {
            const name = [row[LAST_NAME_FIELD.fieldApiName], row[FIRST_NAME_FIELD.fieldApiName]]
                .filter((part) => part)
                .join(', ');
            const parts = [
                row[MRN_FIELD.fieldApiName],
                row[PHONE_FIELD.fieldApiName],
                row[EMAIL_FIELD.fieldApiName],
                formatDob(row[DOB_FIELD.fieldApiName]),
                row[STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: name || 'Patient',
                meta: parts.join(' · '),
                objectApiName: PATIENT_OBJECT.objectApiName
            };
        });
    }

    @api
    focusSearch() {
        const input = this.template.querySelector('lightning-input');
        if (input) {
            input.focus();
        }
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
            const rows = await searchPatients({ searchTerm: trimmed });
            this.patients = await withRecordUrls(this, rows, PATIENT_OBJECT.objectApiName, {
                labelField: LAST_NAME_FIELD.fieldApiName
            });
            this.errorMessage = undefined;
        } catch (error) {
            this.patients = [];
            this.errorMessage = this.reduceError(error);
        }
        this.hasSearched = true;
    }

    handleOpenCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: OPEN_CHART },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
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
