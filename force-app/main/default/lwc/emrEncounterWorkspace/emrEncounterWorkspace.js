import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import transitionStatus from '@salesforce/apex/EncounterWorkspaceController.transitionStatus';
import getDiagnoses from '@salesforce/apex/EncounterWorkspaceController.getDiagnoses';
import addDiagnosis from '@salesforce/apex/EncounterWorkspaceController.addDiagnosis';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import PATIENT_FIRST_NAME_FIELD from '@salesforce/schema/Encounter__c.Patient__r.First_Name__c';
import PATIENT_LAST_NAME_FIELD from '@salesforce/schema/Encounter__c.Patient__r.Last_Name__c';
import STATUS_FIELD from '@salesforce/schema/Encounter__c.Status__c';
import CLASS_FIELD from '@salesforce/schema/Encounter__c.Class__c';
import START_FIELD from '@salesforce/schema/Encounter__c.Start__c';
import END_FIELD from '@salesforce/schema/Encounter__c.End__c';
import LOCATION_FIELD from '@salesforce/schema/Encounter__c.Location_Name__c';
import ATTENDING_FIRST_NAME_FIELD from '@salesforce/schema/Encounter__c.Practitioner__r.First_Name__c';
import ATTENDING_LAST_NAME_FIELD from '@salesforce/schema/Encounter__c.Practitioner__r.Last_Name__c';

const STATUS_PATH = ['Planned', 'Arrived', 'In Progress', 'Finished'];
const NEXT_STATUS = {
    Planned: 'Arrived',
    Arrived: 'In Progress',
    'In Progress': 'Finished'
};

const ENCOUNTER_FIELDS = [
    PATIENT_FIRST_NAME_FIELD,
    PATIENT_LAST_NAME_FIELD,
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
    dxType = 'Principal';
    dxRank = '';
    wiredDiagnosesResult;

    dxCodeSystemOptions = [
        { label: 'ICD-10', value: 'ICD-10' },
        { label: 'SNOMED', value: 'SNOMED' }
    ];

    dxTypeOptions = [
        { label: 'Principal', value: 'Principal' },
        { label: 'Secondary', value: 'Secondary' },
        { label: 'Admitting', value: 'Admitting' },
        { label: 'Discharge', value: 'Discharge' }
    ];

    diagnosisColumns = [
        { label: 'Diagnosis', fieldName: 'display', wrapText: true },
        { label: 'Code', fieldName: 'code' },
        { label: 'System', fieldName: 'codeSystem' },
        { label: 'Type', fieldName: 'diagnosisType' },
        { label: 'Rank', fieldName: 'rank', type: 'number' },
        { label: 'Status', fieldName: 'status' }
    ];

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
            this.diagnoses = data;
            this.diagnosisError = undefined;
        } else if (error) {
            this.diagnoses = [];
            this.diagnosisError = this.reduceError(error);
        }
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

    get patientName() {
        const first = getFieldValue(this.encounter, PATIENT_FIRST_NAME_FIELD) || '';
        const last = getFieldValue(this.encounter, PATIENT_LAST_NAME_FIELD) || '';
        return `${first} ${last}`.trim() || 'Patient';
    }

    get status() {
        return getFieldValue(this.encounter, STATUS_FIELD) || '';
    }

    get encounterClass() {
        return getFieldValue(this.encounter, CLASS_FIELD) || '';
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
        this.showAddDiagnosisForm = !this.showAddDiagnosisForm;
        this.diagnosisError = undefined;
    }

    handleDxCodeSystemChange(event) {
        this.dxCodeSystem = event.detail.value;
    }

    handleDxCodeChange(event) {
        this.dxCode = event.detail.value;
    }

    handleDxDisplayChange(event) {
        this.dxDisplay = event.detail.value;
    }

    handleDxTypeChange(event) {
        this.dxType = event.detail.value;
    }

    handleDxRankChange(event) {
        this.dxRank = event.detail.value;
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
                diagnosisType: this.dxType,
                rank: this.dxRank === '' || this.dxRank === null ? null : Number(this.dxRank)
            });
            this.dxCode = '';
            this.dxDisplay = '';
            this.dxRank = '';
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
