import { LightningElement, api, wire } from 'lwc';
import registerPatient from '@salesforce/apex/PatientRegistrationController.registerPatient';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';

export default class EmrPatientRegistration extends LightningElement {
    @api buttonLabel = 'New Patient';
    @api buttonVariant = 'neutral';

    isOpen = false;
    isSaving = false;
    errorMessage;
    duplicates = [];
    mrn = '';
    firstName = '';
    lastName = '';
    dateOfBirth;
    sexAtBirth;
    phone = '';
    email = '';
    smsOptIn = false;
    status = 'Active';

    sexOptions = [
        { label: 'Male', value: 'Male' },
        { label: 'Female', value: 'Female' },
        { label: 'Unknown', value: 'Unknown' },
        { label: 'Other', value: 'Other' }
    ];

    statusOptions = [
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];

    @wire(getObjectInfo, { objectApiName: PATIENT_OBJECT })
    patientObjectInfo;

    get canRegister() {
        return this.patientObjectInfo.data?.createable === true;
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get hasDuplicates() {
        return this.duplicates.length > 0;
    }

    @api
    open() {
        this.isOpen = true;
        this.errorMessage = undefined;
        this.duplicates = [];
    }

    handleClose() {
        this.isOpen = false;
        this.reset();
    }

    handleInput(event) {
        const { name, value, checked, type } = event.target;
        this[name] = type === 'checkbox' ? checked : value;
        this.duplicates = [];
        this.errorMessage = undefined;
    }

    async handleSave() {
        if (this.isSaving) {
            return;
        }
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        if (!inputs.reduce((valid, input) => input.reportValidity() && valid, true)) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = undefined;
        this.duplicates = [];
        try {
            const result = await registerPatient({
                mrn: this.mrn,
                firstName: this.firstName,
                lastName: this.lastName,
                dateOfBirth: this.dateOfBirth || null,
                sexAtBirth: this.sexAtBirth || null,
                phone: this.phone,
                email: this.email,
                smsOptIn: this.smsOptIn,
                status: this.status
            });
            if (result?.duplicates?.length) {
                this.duplicates = result.duplicates.map((row) => ({
                    ...row,
                    displayName:
                        [row.Last_Name__c, row.First_Name__c].filter((part) => part).join(', ') ||
                        row.Name ||
                        'Patient'
                }));
                this.errorMessage = 'Potential duplicate found. Open the existing chart or change the details.';
                return;
            }
            if (result?.patient?.Id) {
                this.dispatchEvent(
                    new CustomEvent('patientcreated', {
                        bubbles: true,
                        composed: true,
                        detail: { patientId: result.patient.Id }
                    })
                );
                this.isOpen = false;
                this.reset();
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleUseExisting(event) {
        this.dispatchEvent(
            new CustomEvent('patientcreated', {
                bubbles: true,
                composed: true,
                detail: { patientId: event.currentTarget.dataset.id, existing: true }
            })
        );
        this.isOpen = false;
        this.reset();
    }

    reset() {
        this.errorMessage = undefined;
        this.duplicates = [];
        this.mrn = '';
        this.firstName = '';
        this.lastName = '';
        this.dateOfBirth = undefined;
        this.sexAtBirth = undefined;
        this.phone = '';
        this.email = '';
        this.smsOptIn = false;
        this.status = 'Active';
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to register patient.';
    }
}
