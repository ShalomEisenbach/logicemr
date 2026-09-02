import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getProcedures from '@salesforce/apex/ProcedurePanelController.getProcedures';
import addProcedure from '@salesforce/apex/ProcedurePanelController.addProcedure';
import completeProcedures from '@salesforce/apex/ProcedurePanelController.completeProcedures';
import deleteProcedures from '@salesforce/apex/ProcedurePanelController.deleteProcedures';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PROCEDURE_OBJECT from '@salesforce/schema/Procedure__c';
import DISPLAY_FIELD from '@salesforce/schema/Procedure__c.Procedure_Display__c';
import CODE_FIELD from '@salesforce/schema/Procedure__c.Procedure_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/Procedure__c.Procedure_Code_System__c';
import CATEGORY_FIELD from '@salesforce/schema/Procedure__c.Category__c';
import STATUS_FIELD from '@salesforce/schema/Procedure__c.Status__c';
import PERFORMED_FIELD from '@salesforce/schema/Procedure__c.Performed_DateTime__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const COMPLETE = 'complete';
const DELETE = 'delete';

export default class EmrProcedurePanel extends NavigationMixin(LightningElement) {
    @api recordId;

    procedures = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'CPT';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['CPT', 'SNOMED'];
    category = 'Diagnostic';
    status = 'Completed';
    performedDateTime;
    notes = '';
    wiredProceduresResult;

    categoryOptions = [
        { label: 'Surgical', value: 'Surgical' },
        { label: 'Diagnostic', value: 'Diagnostic' },
        { label: 'Therapeutic', value: 'Therapeutic' },
        { label: 'Counseling', value: 'Counseling' },
        { label: 'Education', value: 'Education' }
    ];

    statusOptions = [
        { label: 'Preparation', value: 'Preparation' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'On Hold', value: 'On Hold' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Not Done', value: 'Not Done' },
        { label: 'Stopped', value: 'Stopped' }
    ];

    get columns() {
        return [
            urlColumn('Procedure', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'Category', fieldName: CATEGORY_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            {
                label: 'Performed',
                fieldName: PERFORMED_FIELD.fieldApiName,
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: 'numeric',
                    minute: '2-digit'
                }
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: this.getRowActions.bind(this)
                }
            }
        ];
    }

    @wire(getProcedures, { patientId: '$recordId' })
    wiredProcedures(result) {
        this.wiredProceduresResult = result;
        const { data, error } = result;
        if (data) {
            this.applyProcedures(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.procedures = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyProcedures(data) {
        this.procedures = await withRecordUrls(this, data, PROCEDURE_OBJECT.objectApiName, {
            labelField: DISPLAY_FIELD.fieldApiName
        });
    }

    get hasProcedures() {
        return this.procedures && this.procedures.length > 0;
    }

    get showEmpty() {
        return this.procedures && this.procedures.length === 0 && !this.errorMessage;
    }

    get procedureCards() {
        return (this.procedures || []).map((row) => {
            const status = row[STATUS_FIELD.fieldApiName];
            const parts = [
                row[CODE_FIELD.fieldApiName],
                row[CODE_SYSTEM_FIELD.fieldApiName],
                row[CATEGORY_FIELD.fieldApiName],
                status
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[DISPLAY_FIELD.fieldApiName] || 'Procedure',
                meta: parts.join(' · '),
                performedDateTime: row[PERFORMED_FIELD.fieldApiName],
                canComplete: status !== 'Completed',
                objectApiName: PROCEDURE_OBJECT.objectApiName
            };
        });
    }

    get proceduresRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Procedures__r` : 'Procedures__r';
    }

    getRowActions(row, doneCallback) {
        const actions = [];
        if (row[STATUS_FIELD.fieldApiName] !== 'Completed') {
            actions.push({ label: 'Complete', name: COMPLETE });
        }
        actions.push({ label: 'Delete', name: DELETE });
        doneCallback(actions);
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.proceduresRelationshipApiName,
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
        this.category = 'Diagnostic';
        this.status = 'Completed';
        this.performedDateTime = undefined;
        this.notes = '';
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

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handlePerformedChange(event) {
        this.performedDateTime = event.detail.value || null;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addProcedure({
                patientId: this.recordId,
                codeSystem: this.codeSystem,
                code: this.code,
                display: this.display,
                codeReferenceId: this.codeReferenceId,
                category: this.category,
                status: this.status,
                performedDateTime: this.performedDateTime || null,
                notes: this.notes
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredProceduresResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleCompleteCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: COMPLETE },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
    }

    handleDeleteCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: DELETE },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if ((actionName !== COMPLETE && actionName !== DELETE) || this.isSaving) {
            return;
        }
        if (actionName === DELETE) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this procedure?',
                label: 'Delete procedure',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const procedureIds = [event.detail.row.Id];
            if (actionName === COMPLETE) {
                await completeProcedures({ procedureIds });
            } else {
                await deleteProcedures({ procedureIds });
            }
            await refreshApex(this.wiredProceduresResult);
            this.dispatchEvent(new RefreshEvent());
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
        return error?.message || 'Unable to update procedures.';
    }
}
