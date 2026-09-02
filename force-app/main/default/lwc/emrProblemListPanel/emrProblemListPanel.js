import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getProblems from '@salesforce/apex/ProblemListController.getProblems';
import LightningConfirm from 'lightning/confirm';
import addProblem from '@salesforce/apex/ProblemListController.addProblem';
import updateOnsetDate from '@salesforce/apex/ProblemListController.updateOnsetDate';
import resolveProblems from '@salesforce/apex/ProblemListController.resolveProblems';
import reopenProblems from '@salesforce/apex/ProblemListController.reopenProblems';
import deleteProblems from '@salesforce/apex/ProblemListController.deleteProblems';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import CONDITION_OBJECT from '@salesforce/schema/Condition__c';
import DISPLAY_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Display__c';
import CODE_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/Condition__c.Diagnosis_Code_System__c';
import STATUS_FIELD from '@salesforce/schema/Condition__c.Clinical_Status__c';
import ONSET_FIELD from '@salesforce/schema/Condition__c.Onset_Date__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const RESOLVE = 'resolve';
const REOPEN = 'reopen';
const SET_ONSET = 'setOnset';
const DELETE = 'delete';

export default class EmrProblemListPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    activeProblems = [];
    resolvedProblems = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    showOnsetForm = false;
    editingConditionId;
    onsetDate;
    codeSystem = 'ICD-10';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['ICD-10', 'SNOMED'];
    wiredProblemsResult;

    get activeColumns() {
        return [
            urlColumn('Problem', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            { label: 'Onset', fieldName: ONSET_FIELD.fieldApiName, type: 'date' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Set onset', name: SET_ONSET },
                        { label: 'Resolve', name: RESOLVE },
                        { label: 'Delete', name: DELETE }
                    ]
                }
            }
        ];
    }

    get resolvedColumns() {
        return [
            urlColumn('Problem', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            { label: 'Onset', fieldName: ONSET_FIELD.fieldApiName, type: 'date' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Set onset', name: SET_ONSET },
                        { label: 'Reopen', name: REOPEN },
                        { label: 'Delete', name: DELETE }
                    ]
                }
            }
        ];
    }

    get conditionObjectApiName() {
        return CONDITION_OBJECT.objectApiName;
    }

    @wire(getProblems, { patientId: '$recordId' })
    wiredProblems(result) {
        this.wiredProblemsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyProblems(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.activeProblems = [];
            this.resolvedProblems = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyProblems(data) {
        this.activeProblems = await withRecordUrls(
            this,
            data.activeProblems || [],
            CONDITION_OBJECT.objectApiName,
            { labelField: DISPLAY_FIELD.fieldApiName }
        );
        this.resolvedProblems = await withRecordUrls(
            this,
            data.resolvedProblems || [],
            CONDITION_OBJECT.objectApiName,
            { labelField: DISPLAY_FIELD.fieldApiName }
        );
    }

    get hasActive() {
        return this.activeProblems.length > 0;
    }

    get hasResolved() {
        return this.resolvedProblems.length > 0;
    }

    get hasRecords() {
        return this.hasActive || this.hasResolved;
    }

    get showEmpty() {
        return (
            !this.errorMessage &&
            this.wiredProblemsResult?.data &&
            !this.hasActive &&
            !this.hasResolved
        );
    }

    get activeProblemCards() {
        return this.toProblemCards(this.activeProblems);
    }

    get resolvedProblemCards() {
        return this.toProblemCards(this.resolvedProblems);
    }

    toProblemCards(rows) {
        return (rows || []).map((row) => {
            const title = row[DISPLAY_FIELD.fieldApiName] || 'Problem';
            const parts = [
                row[CODE_FIELD.fieldApiName],
                row[CODE_SYSTEM_FIELD.fieldApiName],
                row[STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title,
                meta: parts.join(' · '),
                onsetDate: row[ONSET_FIELD.fieldApiName],
                objectApiName: CONDITION_OBJECT.objectApiName
            };
        });
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
        this.showAddForm = true;
        this.errorMessage = undefined;
    }

    handleCloseAdd() {
        this.showAddForm = false;
        this.errorMessage = undefined;
        this.resetAddForm();
    }

    resetAddForm() {
        this.code = '';
        this.display = '';
        this.codeReferenceId = undefined;
        this.codeSearchValue = undefined;
        this.onsetDate = undefined;
    }

    handleOnsetChange(event) {
        this.onsetDate = event.detail.value || null;
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
                codeReferenceId: this.codeReferenceId,
                onsetDate: this.onsetDate || null
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredProblemsResult);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleResolveCard(event) {
        this.dispatchRowAction(RESOLVE, event.currentTarget.dataset.id);
    }

    handleReopenCard(event) {
        this.dispatchRowAction(REOPEN, event.currentTarget.dataset.id);
    }

    handleDeleteCard(event) {
        this.dispatchRowAction(DELETE, event.currentTarget.dataset.id);
    }

    handleSetOnsetCard(event) {
        this.openOnsetForm({
            Id: event.currentTarget.dataset.id,
            [ONSET_FIELD.fieldApiName]: event.currentTarget.dataset.onset
        });
    }

    openOnsetForm(row) {
        this.editingConditionId = row.Id;
        this.onsetDate = row[ONSET_FIELD.fieldApiName] || null;
        this.showOnsetForm = true;
        this.errorMessage = undefined;
    }

    handleCloseOnset() {
        this.showOnsetForm = false;
        this.editingConditionId = undefined;
        this.onsetDate = undefined;
        this.errorMessage = undefined;
    }

    async handleSaveOnset() {
        if (this.isSaving || !this.editingConditionId) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await updateOnsetDate({
                conditionId: this.editingConditionId,
                onsetDate: this.onsetDate || null
            });
            this.handleCloseOnset();
            await refreshApex(this.wiredProblemsResult);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    dispatchRowAction(name, recordId) {
        this.handleRowAction({
            detail: {
                action: { name },
                row: { Id: recordId }
            }
        });
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if (actionName === SET_ONSET) {
            this.openOnsetForm(event.detail.row);
            return;
        }
        if (
            (actionName !== RESOLVE && actionName !== REOPEN && actionName !== DELETE) ||
            this.isSaving
        ) {
            return;
        }
        if (actionName === DELETE) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this problem?',
                label: 'Delete problem',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const conditionIds = [event.detail.row.Id];
            if (actionName === RESOLVE) {
                await resolveProblems({ conditionIds });
            } else if (actionName === REOPEN) {
                await reopenProblems({ conditionIds });
            } else {
                await deleteProblems({ conditionIds });
            }
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
