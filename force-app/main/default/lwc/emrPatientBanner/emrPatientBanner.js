import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import resolvePatientId from '@salesforce/apex/AlertBarController.resolvePatientId';
import getActiveAllergies from '@salesforce/apex/AllergyPanelController.getActiveAllergies';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';
import DISPLAY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Display__c';
import CODE_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Code__c';

const PATIENT_FIELDS = [
    FIRST_NAME_FIELD,
    LAST_NAME_FIELD,
    DOB_FIELD,
    MRN_FIELD,
    STATUS_FIELD
];

export default class EmrPatientBanner extends LightningElement {
    @api recordId;

    patientId;
    patient;
    errorMessage;
    activeAllergies = [];
    wiredAllergiesResult;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        if (!this.wiredAllergiesResult) {
            return Promise.resolve();
        }
        return refreshApex(this.wiredAllergiesResult);
    }

    @wire(resolvePatientId, { recordId: '$recordId' })
    wiredResolvedPatient({ data, error }) {
        if (error) {
            this.patientId = undefined;
            this.errorMessage = this.reduceError(error);
            return;
        }
        this.patientId = data || undefined;
        if (data) {
            this.errorMessage = undefined;
        }
    }

    @wire(getRecord, { recordId: '$patientId', fields: PATIENT_FIELDS })
    wiredPatient({ data, error }) {
        this.patient = data;
        if (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    @wire(getActiveAllergies, { patientId: '$patientId' })
    wiredAllergies(result) {
        this.wiredAllergiesResult = result;
        if (result.data) {
            this.activeAllergies = result.data;
        } else if (result.error) {
            this.activeAllergies = [];
        }
    }

    get hasPatient() {
        return !!this.patient;
    }

    get patientName() {
        const first = getFieldValue(this.patient, FIRST_NAME_FIELD) || '';
        const last = getFieldValue(this.patient, LAST_NAME_FIELD) || '';
        return `${first} ${last}`.trim() || 'Patient';
    }

    get ageLabel() {
        const dob = getFieldValue(this.patient, DOB_FIELD);
        if (!dob) {
            return '';
        }
        const birth = new Date(dob);
        if (Number.isNaN(birth.getTime())) {
            return '';
        }
        const today = new Date();
        let years = today.getFullYear() - birth.getFullYear();
        let months = today.getMonth() - birth.getMonth();
        if (today.getDate() < birth.getDate()) {
            months -= 1;
        }
        if (months < 0) {
            years -= 1;
            months += 12;
        }
        if (years < 0) {
            return '';
        }
        if (years === 0) {
            return months === 1 ? '1 month' : `${months} months`;
        }
        return years === 1 ? '1 year' : `${years} years`;
    }

    get mrn() {
        return getFieldValue(this.patient, MRN_FIELD) || '';
    }

    get status() {
        return getFieldValue(this.patient, STATUS_FIELD) || '';
    }

    get allergyCount() {
        return this.activeAllergies.length;
    }

    get allergyCountLabel() {
        const count = this.allergyCount;
        return count === 1 ? '1 active' : `${count} active`;
    }

    get allergyNames() {
        if (!this.activeAllergies.length) {
            return 'None';
        }
        return this.activeAllergies
            .map((row) => row[DISPLAY_FIELD.fieldApiName] || row[CODE_FIELD.fieldApiName] || '')
            .filter((name) => name)
            .join(', ');
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load patient.';
    }
}
