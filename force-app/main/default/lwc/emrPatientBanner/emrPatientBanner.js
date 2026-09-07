import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import resolvePatientId from '@salesforce/apex/AlertBarController.resolvePatientId';
import getLatestVitals from '@salesforce/apex/PatientBannerController.getLatestVitals';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';
import SEX_FIELD from '@salesforce/schema/Patient__c.Sex_at_Birth__c';
import PHONE_FIELD from '@salesforce/schema/Patient__c.Phone__c';
import EMAIL_FIELD from '@salesforce/schema/Patient__c.Email__c';

const PATIENT_FIELDS = [
    FIRST_NAME_FIELD,
    LAST_NAME_FIELD,
    DOB_FIELD,
    MRN_FIELD,
    STATUS_FIELD,
    SEX_FIELD,
    PHONE_FIELD,
    EMAIL_FIELD
];

export default class EmrPatientBanner extends LightningElement {
    @api recordId;

    patientId;
    patient;
    errorMessage;
    vitalItems = [];
    vitalsRecordedAt;
    wiredVitalsResult;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        if (!this.wiredVitalsResult) {
            return Promise.resolve();
        }
        return refreshApex(this.wiredVitalsResult);
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

    @wire(getLatestVitals, { patientId: '$vitalsPatientId' })
    wiredVitals(result) {
        this.wiredVitalsResult = result;
        if (result.data) {
            this.vitalItems = result.data.items || [];
            this.vitalsRecordedAt = result.data.recordedAt;
        } else if (result.error) {
            this.vitalItems = [];
            this.vitalsRecordedAt = undefined;
        }
    }

    get showVitals() {
        return !!(this.recordId && this.patientId && this.recordId === this.patientId);
    }

    get vitalsPatientId() {
        return this.showVitals ? this.patientId : undefined;
    }

    get hasPatient() {
        return !!this.patient;
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get emptyValue() {
        return '—';
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
        return getFieldValue(this.patient, MRN_FIELD) || this.emptyValue;
    }

    get dateOfBirth() {
        return getFieldValue(this.patient, DOB_FIELD) || '';
    }

    get sexAtBirth() {
        return getFieldValue(this.patient, SEX_FIELD) || this.emptyValue;
    }

    get phone() {
        return getFieldValue(this.patient, PHONE_FIELD) || '';
    }

    get email() {
        return getFieldValue(this.patient, EMAIL_FIELD) || '';
    }

    get status() {
        return getFieldValue(this.patient, STATUS_FIELD) || '';
    }

    get showDocumentActions() {
        return !!(this.recordId && this.patientId && this.recordId === this.patientId);
    }

    get statusBadgeClass() {
        const normalized = (this.status || '').toLowerCase();
        if (normalized === 'active') {
            return 'status-badge status-badge_active';
        }
        if (normalized === 'inactive') {
            return 'status-badge status-badge_inactive';
        }
        return 'status-badge';
    }

    get hasVitals() {
        return this.vitalItems.length > 0;
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
