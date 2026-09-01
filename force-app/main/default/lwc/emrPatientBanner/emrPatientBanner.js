import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';

const PATIENT_FIELDS = [
    FIRST_NAME_FIELD,
    LAST_NAME_FIELD,
    DOB_FIELD,
    MRN_FIELD,
    STATUS_FIELD
];

export default class EmrPatientBanner extends LightningElement {
    @api recordId;

    patient;
    errorMessage;

    @wire(getRecord, { recordId: '$recordId', fields: PATIENT_FIELDS })
    wiredPatient({ data, error }) {
        this.patient = data;
        this.errorMessage = error ? this.reduceError(error) : undefined;
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
