import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import transitionStatus from '@salesforce/apex/EncounterWorkspaceController.transitionStatus';
import getDiagnoses from '@salesforce/apex/EncounterWorkspaceController.getDiagnoses';
import addDiagnosis from '@salesforce/apex/EncounterWorkspaceController.addDiagnosis';
import deleteDiagnoses from '@salesforce/apex/EncounterWorkspaceController.deleteDiagnoses';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import CONDITION_OBJECT from '@salesforce/schema/Condition__c';
import PATIENT_FIELD from '@salesforce/schema/Encounter__c.Patient__c';
import PRACTITIONER_FIELD from '@salesforce/schema/Encounter__c.Practitioner__c';
import PATIENT_FIRST_NAME_FIELD from '@salesforce/schema/Encounter__c.Patient__r.First_Name__c';
import PATIENT_LAST_NAME_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Last_Name__c';
import PATIENT_DOB_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Date_of_Birth__c';
import PATIENT_SEX_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Sex_at_Birth__c';
import PATIENT_MRN_FIELD from '@salesforce/schema/Encounter__c.Patient__r.MRN__c';
import PATIENT_PHONE_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Phone__c';
import PATIENT_EMAIL_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Email__c';
import STATUS_FIELD from '@salesforce/schema/Encounter__c.Status__c';
import CLASS_FIELD from '@salesforce/schema/Encounter__c.Class__c';
import START_FIELD from '@salesforce/schema/Encounter__c.Start__c';
import END_FIELD from '@salesforce/schema/Encounter__c.End__c';
import LOCATION_FIELD from '@salesforce/schema/Encounter__c.Location_Name__c';
import ATTENDING_FIRST_NAME_FIELD from '@salesforce/schema/Encounter__c.Practitioner__r.First_Name__c';
import ATTENDING_LAST_NAME_FIELD from '@salesforce/schema/Encounter__c.Practitioner__r.Last_Name__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const DELETE = 'delete';
const STATUS_PATH = ['Planned', 'Arrived', 'In Progress', 'Finished'];
const NEXT_STATUS = {
    Planned: 'Arrived',
    Arrived: 'In Progress',
    'In Progress': 'Finished'
};

const ENCOUNTER_FIELDS = [
    PATIENT_FIELD,
    PRACTITIONER_FIELD,
    PATIENT_FIRST_NAME_FIELD,
    PATIENT_LAST_NAME_FIELD,
    PATIENT_DOB_FIELD,
    PATIENT_SEX_FIELD,
    PATIENT_MRN_FIELD,
    PATIENT_PHONE_FIELD,
    PATIENT_EMAIL_FIELD,
    STATUS_FIELD,
    CLASS_FIELD,
    START_FIELD,
    END_FIELD,
    LOCATION_FIELD,
    ATTENDING_FIRST_NAME_FIELD,
    ATTENDING_LAST_NAME_FIELD
];

export default class EmrEncounterWorkspace extends NavigationMixin(LightningElement) {
    @api recordId;

    encounter;
    errorMessage;
    isSaving = false;
    diagnoses = [];
    diagnosisError;
    isSavingDiagnosis = false;
    showAddDiagnosisForm = false;
    dxCodeSystem = 'ICD-10';
    dxCode = '';
    dxDisplay = '';
    dxCodeReferenceId;
    codeSearchValue;
    codeSystems = ['ICD-10', 'SNOMED'];
    dxType = 'Principal';
    dxRank = '';
    wiredDiagnosesResult;

    dxTypeOptions = [
        { label: 'Principal', value: 'Principal' },
        { label: 'Secondary', value: 'Secondary' },
        { label: 'Admitting', value: 'Admitting' },
        { label: 'Discharge', value: 'Discharge' }
    ];

    get diagnosisColumns() {
        return [
            urlColumn('Diagnosis', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: 'code' },
            { label: 'System', fieldName: 'codeSystem' },
            { label: 'Type', fieldName: 'diagnosisType' },
            { label: 'Rank', fieldName: 'rank', type: 'number' },
            { label: 'Status', fieldName: 'status' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Delete', name: DELETE }]
                }
            }
        ];
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get encounterObjectApiName() {
        return ENCOUNTER_OBJECT.objectApiName;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    @wire(getRecord, { recordId: '$recordId', fields: ENCOUNTER_FIELDS })
    wiredEncounter({ data, error }) {
        this.encounter = data;
        this.errorMessage = error ? this.reduceError(error) : undefined;
    }

    @wire(getDiagnoses, { encounterId: '$recordId' })
    wiredDiagnoses(result) {
        this.wiredDiagnosesResult = result;
        const { data, error } = result;
        if (data) {
            this.applyDiagnoses(data);
            this.diagnosisError = undefined;
        } else if (error) {
            this.diagnoses = [];
            this.diagnosisError = this.reduceError(error);
        }
    }

    async applyDiagnoses(data) {
        this.diagnoses = await withRecordUrls(
            this,
            data || [],
            CONDITION_OBJECT.objectApiName,
            {
                idField: 'conditionId',
                labelField: 'display'
            }
        );
    }

    get hasDiagnoses() {
        return this.diagnoses && this.diagnoses.length > 0;
    }

    get showEmptyDiagnoses() {
        return !this.diagnosisError && this.wiredDiagnosesResult?.data && !this.hasDiagnoses;
    }

    get diagnosesRelationshipApiName() {
        const objectApiName = ENCOUNTER_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__EncounterDiagnoses__r` : 'EncounterDiagnoses__r';
    }

    get hasEncounter() {
        return !!this.encounter;
    }

    get patientId() {
        return getFieldValue(this.encounter, PATIENT_FIELD);
    }

    get attendingId() {
        return getFieldValue(this.encounter, PRACTITIONER_FIELD);
    }

    get patientName() {
        const first = getFieldValue(this.encounter, PATIENT_FIRST_NAME_FIELD) || '';
        const last = getFieldValue(this.encounter, PATIENT_LAST_NAME_FIELD) || '';
        return `${first} ${last}`.trim() || 'Patient';
    }

    get emptyValue() {
        return '—';
    }

    get ageLabel() {
        const dob = getFieldValue(this.encounter, PATIENT_DOB_FIELD);
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
        return getFieldValue(this.encounter, PATIENT_MRN_FIELD) || this.emptyValue;
    }

    get dateOfBirth() {
        return getFieldValue(this.encounter, PATIENT_DOB_FIELD) || '';
    }

    get sexAtBirth() {
        return getFieldValue(this.encounter, PATIENT_SEX_FIELD) || this.emptyValue;
    }

    get phone() {
        return getFieldValue(this.encounter, PATIENT_PHONE_FIELD) || '';
    }

    get email() {
        return getFieldValue(this.encounter, PATIENT_EMAIL_FIELD) || '';
    }

    get status() {
        return getFieldValue(this.encounter, STATUS_FIELD) || '';
    }

    get statusBadgeClass() {
        const normalized = (this.status || '').toLowerCase();
        if (normalized === 'in progress') {
            return 'status-badge status-badge_progress';
        }
        if (normalized === 'arrived') {
            return 'status-badge status-badge_arrived';
        }
        if (normalized === 'finished') {
            return 'status-badge status-badge_finished';
        }
        if (normalized === 'cancelled') {
            return 'status-badge status-badge_cancelled';
        }
        return 'status-badge status-badge_planned';
    }

    get encounterClass() {
        return getFieldValue(this.encounter, CLASS_FIELD) || '';
    }

    get identitySubtitle() {
        const parts = [];
        if (this.ageLabel) {
            parts.push(this.ageLabel);
        }
        if (this.encounterClass) {
            parts.push(this.encounterClass);
        }
        return parts.join(' · ');
    }

    get startValue() {
        return getFieldValue(this.encounter, START_FIELD);
    }

    get endValue() {
        return getFieldValue(this.encounter, END_FIELD);
    }

    get locationName() {
        return getFieldValue(this.encounter, LOCATION_FIELD) || '';
    }

    get attendingName() {
        const first = getFieldValue(this.encounter, ATTENDING_FIRST_NAME_FIELD) || '';
        const last = getFieldValue(this.encounter, ATTENDING_LAST_NAME_FIELD) || '';
        return `${first} ${last}`.trim();
    }

    get nextStatus() {
        return NEXT_STATUS[this.status];
    }

    get canAdvance() {
        return !!this.nextStatus && this.isClientTransitionValid(this.status, this.nextStatus);
    }

    get advanceLabel() {
        return this.nextStatus ? `Mark ${this.nextStatus}` : '';
    }

    get statusSteps() {
        const current = this.status;
        const currentIndex = STATUS_PATH.indexOf(current);
        return STATUS_PATH.map((label, index) => {
            let tone = 'upcoming';
            if (current === 'Cancelled') {
                tone = 'upcoming';
            } else if (index < currentIndex) {
                tone = 'complete';
            } else if (index === currentIndex) {
                tone = 'current';
            }
            return {
                label,
                tone,
                className: `status-step status-step_${tone}`,
                key: label
            };
        });
    }

    isClientTransitionValid(currentStatus, newStatus) {
        if (!currentStatus || !newStatus) {
            return false;
        }
        return NEXT_STATUS[currentStatus] === newStatus;
    }

    async handleAdvance() {
        const currentStatus = this.status;
        const newStatus = this.nextStatus;
        if (!this.isClientTransitionValid(currentStatus, newStatus)) {
            this.errorMessage = `Cannot change status from ${currentStatus || '(none)'} to ${
                newStatus || '(none)'
            }.`;
            return;
        }

        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await transitionStatus({
                encounterId: this.recordId,
                newStatus
            });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Status updated',
                    message: `Encounter is now ${newStatus}.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleViewAllDiagnoses() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: ENCOUNTER_OBJECT.objectApiName,
                relationshipApiName: this.diagnosesRelationshipApiName,
                actionName: 'view'
            }
        });
    }

    handleToggleAddDiagnosis() {
        this.showAddDiagnosisForm = true;
        this.diagnosisError = undefined;
    }

    handleCloseAddDiagnosis() {
        this.showAddDiagnosisForm = false;
        this.diagnosisError = undefined;
        this.resetDiagnosisForm();
    }

    resetDiagnosisForm() {
        this.dxCode = '';
        this.dxDisplay = '';
        this.dxCodeReferenceId = undefined;
        this.codeSearchValue = undefined;
        this.dxRank = '';
    }

    handleCodeSelected(event) {
        this.dxCodeSystem = event.detail.system;
        this.dxCode = event.detail.code;
        this.dxDisplay = event.detail.display;
        this.dxCodeReferenceId = event.detail.recordId;
        if (event.detail.code || event.detail.display) {
            this.codeSearchValue = event.detail;
        }
    }

    handleDxTypeChange(event) {
        this.dxType = event.detail.value;
    }

    handleDxRankChange(event) {
        this.dxRank = event.detail.value;
    }

    async handleDiagnosisRowAction(event) {
        if (event.detail.action.name !== DELETE || this.isSavingDiagnosis) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: 'Delete this diagnosis?',
            label: 'Delete diagnosis',
            theme: 'error'
        });
        if (!confirmed) {
            return;
        }
        this.isSavingDiagnosis = true;
        this.diagnosisError = undefined;
        try {
            await deleteDiagnoses({ encounterDiagnosisIds: [event.detail.row.id] });
            await refreshApex(this.wiredDiagnosesResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.diagnosisError = this.reduceError(error);
        } finally {
            this.isSavingDiagnosis = false;
        }
    }

    async handleSaveDiagnosis() {
        if (this.isSavingDiagnosis) {
            return;
        }
        this.isSavingDiagnosis = true;
        this.diagnosisError = undefined;
        try {
            await addDiagnosis({
                encounterId: this.recordId,
                codeSystem: this.dxCodeSystem,
                code: this.dxCode,
                display: this.dxDisplay,
                codeReferenceId: this.dxCodeReferenceId,
                diagnosisType: this.dxType,
                rank: this.dxRank === '' || this.dxRank === null ? null : Number(this.dxRank)
            });
            this.resetDiagnosisForm();
            this.showAddDiagnosisForm = false;
            await refreshApex(this.wiredDiagnosesResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.diagnosisError = this.reduceError(error);
        } finally {
            this.isSavingDiagnosis = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to update encounter.';
    }
}
