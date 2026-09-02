import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getProblems from '@salesforce/apex/ProblemListController.getProblems';
import addProblem from '@salesforce/apex/ProblemListController.addProblem';
import resolveProblems from '@salesforce/apex/ProblemListController.resolveProblems';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import DISPLAY_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Display__c';
import CODE_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Code_System__c';
import STATUS_FIELD from '@salesforce/schema/Condition__c.Clinical_Status__c';
import ONSET_FIELD from '@salesforce/schema/Condition__c.Onset_Date__c';

const RESOLVE = 'resolve';

export default class EmrProblemListPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    activeProblems = [];
    resolvedProblems = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'ICD-10';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['ICD-10', 'SNOMED'];
    wiredProblemsResult;

    activeColumns = [
        { label: 'Problem', fieldName: DISPLAY_FIELD.fieldApiName, wrapText: true },
        { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
        { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
        { label: 'Onset', fieldName: ONSET_FIELD.fieldApiName, type: 'date' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Resolve', name: RESOLVE }]
            }
        }
    ];

    resolvedColumns = [
        { label: 'Problem', fieldName: DISPLAY_FIELD.fieldApiName, wrapText: true },
        { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
        { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName }
    ];

    @wire(getProblems, { patientId: '$recordId' })
    wiredProblems(result) {
        this.wiredProblemsResult = result;
        const { data, error } = result;
        if (data) {
            this.activeProblems = data.activeProblems || [];
            this.resolvedProblems = data.resolvedProblems || [];
            this.errorMessage = undefined;
        } else if (error) {
            this.activeProblems = [];
            this.resolvedProblems = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasActive() {
        return this.activeProblems.length > 0;
    }

    get hasResolved() {
        return this.resolvedProblems.length > 0;
    }

    get showEmpty() {
        return (
            !this.errorMessage &&
            this.wiredProblemsResult?.data &&
            !this.hasActive &&
            !this.hasResolved
        );
    }

    get conditionsRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Conditions__r` : 'Conditions__r';
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.conditionsRelationshipApiName,
                actionName: 'view'
            }
        });
    }

    handleToggleAdd() {
        this.showAddForm = !this.showAddForm;
        this.errorMessage = undefined;
    }

    handleCodeSelected(event) {
        this.codeSystem = event.detail.system;
        this.code = event.detail.code;
        this.display = event.detail.display;
        this.codeReferenceId = event.detail.recordId;
        if (event.detail.code || event.detail.display) {
            this.codeSearchValue = event.detail;
        }
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addProblem({
                patientId: this.recordId,
                codeSystem: this.codeSystem,
                code: this.code,
                display: this.display,
                codeReferenceId: this.codeReferenceId
            });
            this.code = '';
            this.display = '';
            this.codeReferenceId = undefined;
            this.codeSearchValue = undefined;
            this.showAddForm = false;
            await refreshApex(this.wiredProblemsResult);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRowAction(event) {
        if (event.detail.action.name !== RESOLVE || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await resolveProblems({ conditionIds: [event.detail.row.Id] });
            await refreshApex(this.wiredProblemsResult);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to update problems.';
    }
}
