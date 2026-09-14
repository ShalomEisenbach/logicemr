import { LightningElement, api, wire } from 'lwc';
import registerPatient from '@salesforce/apex/PatientRegistrationController.registerPatient';
import updatePatientDemographics from '@salesforce/apex/PatientRegistrationController.updatePatientDemographics';
import getPatientDemographics from '@salesforce/apex/PatientRegistrationController.getPatientDemographics';
import getCoverages from '@salesforce/apex/CoveragePanelController.getCoverages';
import saveCoverage from '@salesforce/apex/CoveragePanelController.saveCoverage';
import runCheck from '@salesforce/apex/EligibilityCheckController.runCheck';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import COVERAGE_OBJECT from '@salesforce/schema/Coverage__c';
import PAYER_OBJECT from '@salesforce/schema/Payer__c';
import PAYER_ACTIVE_FIELD from '@salesforce/schema/Payer__c.Active__c';
import hasRunEligibility from '@salesforce/customPermission/LogicEMR_Run_Eligibility';

export default class EmrPatientRegistration extends LightningElement {
    @api buttonLabel = 'New Patient';
    @api buttonVariant = 'neutral';

    isOpen = false;
    isSaving = false;
    isLoading = false;
    isEditMode = false;
    patientId;
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
    street = '';
    city = '';
    state = '';
    postalCode = '';
    country = 'US';
    coverageId;
    payerId;
    memberId = '';
    groupNumber = '';
    relationshipToSubscriber = 'Self';
    subscriberName = '';
    checkEligibility = false;

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

    relationshipOptions = [
        { label: 'Self', value: 'Self' },
        { label: 'Spouse', value: 'Spouse' },
        { label: 'Child', value: 'Child' },
        { label: 'Other', value: 'Other' }
    ];

    payerFilter = {
        criteria: [
            {
                fieldPath: PAYER_ACTIVE_FIELD.fieldApiName,
                operator: 'eq',
                value: true
            }
        ]
    };

    @wire(getObjectInfo, { objectApiName: PATIENT_OBJECT })
    patientObjectInfo;

    @wire(getObjectInfo, { objectApiName: COVERAGE_OBJECT })
    coverageObjectInfo;

    get canRegister() {
        return this.patientObjectInfo.data?.createable === true;
    }

    get canEdit() {
        return this.patientObjectInfo.data?.updateable === true;
    }

    get showNewButton() {
        return this.canRegister && !this.isEditMode;
    }

    get showCoverageSection() {
        const info = this.coverageObjectInfo.data;
        return info?.createable === true || info?.updateable === true;
    }

    get canRunEligibility() {
        return hasRunEligibility === true;
    }

    get payerObjectApiName() {
        return PAYER_OBJECT.objectApiName;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit demographics' : 'Register patient';
    }

    get saveLabel() {
        return this.isEditMode ? 'Save' : 'Register patient';
    }

    get mrnDisabled() {
        return this.isEditMode;
    }

    get hasDuplicates() {
        return this.duplicates.length > 0;
    }

    @api
    open() {
        this.isEditMode = false;
        this.patientId = undefined;
        this.isOpen = true;
        this.errorMessage = undefined;
        this.duplicates = [];
        this.isLoading = false;
        this.resetForm();
        this.checkEligibility = this.canRunEligibility;
    }

    @api
    async openForEdit(patientId) {
        if (!patientId) {
            return;
        }
        this.isEditMode = true;
        this.patientId = patientId;
        this.isOpen = true;
        this.errorMessage = undefined;
        this.duplicates = [];
        this.isLoading = true;
        this.resetForm();
        this.checkEligibility = this.canRunEligibility;
        try {
            const row = await getPatientDemographics({ patientId });
            this.mrn = row.MRN__c || '';
            this.firstName = row.First_Name__c || '';
            this.lastName = row.Last_Name__c || '';
            this.dateOfBirth = row.Date_of_Birth__c || undefined;
            this.sexAtBirth = row.Sex_at_Birth__c || undefined;
            this.phone = row.Phone__c || '';
            this.email = row.Email__c || '';
            this.smsOptIn = row.SMS_Opt_In__c === true;
            this.status = row.Status__c || 'Active';
            this.street = row.Street__c || '';
            this.city = row.City__c || '';
            this.state = row.State__c || '';
            this.postalCode = row.Postal_Code__c || '';
            this.country = row.Country__c || 'US';
            await this.loadPrimaryCoverage(patientId);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
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

    handlePayerChange(event) {
        this.payerId = event.detail.recordId;
        this.duplicates = [];
        this.errorMessage = undefined;
    }

    async handleSave() {
        if (this.isSaving || this.isLoading) {
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
            const demographics = this.buildDemographics();
            let savedPatientId = this.patientId;
            if (this.isEditMode) {
                await updatePatientDemographics({ input: demographics });
            } else {
                const result = await registerPatient({ input: demographics });
                if (result?.duplicates?.length) {
                    this.duplicates = result.duplicates.map((row) => ({
                        ...row,
                        displayName:
                            [row.Last_Name__c, row.First_Name__c].filter((part) => part).join(', ') ||
                            row.Name ||
                            'Patient'
                    }));
                    this.errorMessage =
                        'Potential duplicate found. Open the existing chart or change the details.';
                    return;
                }
                if (!result?.patient?.Id) {
                    return;
                }
                savedPatientId = result.patient.Id;
            }

            await this.saveInsurance(savedPatientId);

            this.dispatchEvent(
                new CustomEvent(this.isEditMode ? 'patientupdated' : 'patientcreated', {
                    bubbles: true,
                    composed: true,
                    detail: { patientId: savedPatientId }
                })
            );
            this.isOpen = false;
            this.reset();
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
        this.isEditMode = false;
        this.patientId = undefined;
        this.isLoading = false;
        this.resetForm();
    }

    resetForm() {
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
        this.street = '';
        this.city = '';
        this.state = '';
        this.postalCode = '';
        this.country = 'US';
        this.coverageId = undefined;
        this.payerId = undefined;
        this.memberId = '';
        this.groupNumber = '';
        this.relationshipToSubscriber = 'Self';
        this.subscriberName = '';
        this.checkEligibility = false;
    }

    buildDemographics() {
        return {
            patientId: this.isEditMode ? this.patientId : undefined,
            mrn: this.mrn,
            firstName: this.firstName,
            lastName: this.lastName,
            dateOfBirth: this.dateOfBirth || null,
            sexAtBirth: this.sexAtBirth || null,
            phone: this.phone,
            email: this.email,
            smsOptIn: this.smsOptIn,
            status: this.status,
            street: this.street,
            city: this.city,
            state: this.state,
            postalCode: this.postalCode,
            country: this.country
        };
    }

    async loadPrimaryCoverage(patientId) {
        try {
            const rows = await getCoverages({ patientId });
            const first = rows?.[0]?.coverage;
            if (!first) {
                return;
            }
            this.coverageId = first.Id;
            this.payerId = first.Payer__c;
            this.memberId = first.Member_Id__c || '';
            this.groupNumber = first.Group_Number__c || '';
            this.relationshipToSubscriber = first.Relationship_to_Subscriber__c || 'Self';
            this.subscriberName = first.Subscriber_Name__c || '';
        } catch (e) {
            // Coverage is optional at registration when the user cannot read Coverage.
        }
    }

    async saveInsurance(patientId) {
        if (!this.showCoverageSection || !this.payerId || !patientId) {
            return;
        }
        const coverage = await saveCoverage({
            coverageId: this.coverageId || null,
            patientId,
            payerId: this.payerId,
            memberId: this.memberId,
            groupNumber: this.groupNumber,
            planName: null,
            coverageType: 'Medical',
            relationshipToSubscriber: this.relationshipToSubscriber || 'Self',
            subscriberName: this.subscriberName,
            status: 'Active',
            effectiveStart: null,
            effectiveEnd: null,
            priority: 'Primary'
        });
        if (this.checkEligibility && this.canRunEligibility && coverage?.Id) {
            await runCheck({ coverageId: coverage.Id });
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to save patient.';
    }
}
