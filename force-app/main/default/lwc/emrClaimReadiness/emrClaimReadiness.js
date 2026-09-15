import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getWorkspace from '@salesforce/apex/ClaimReadinessController.getWorkspace';
import initializeSuperbill from '@salesforce/apex/ClaimReadinessController.initializeSuperbill';
import saveCharge from '@salesforce/apex/ClaimReadinessController.saveCharge';
import deleteCharge from '@salesforce/apex/ClaimReadinessController.deleteCharge';
import markReady from '@salesforce/apex/ClaimReadinessController.markReady';
import reopen from '@salesforce/apex/ClaimReadinessController.reopen';

const EDIT = 'edit';
const DELETE = 'delete';

export default class EmrClaimReadiness extends LightningElement {
    @api recordId;

    workspace;
    errorMessage;
    isLoading = true;
    isSaving = false;
    showChargeModal = false;
    editingChargeId;
    codeSearchValue;
    codeSystems = ['CPT', 'HCPCS'];
    chargeDraft = this.emptyCharge();

    diagnosisColumns = [
        { label: '#', fieldName: 'sequence', type: 'number', initialWidth: 56 },
        { label: 'Type', fieldName: 'type' },
        { label: 'Code', fieldName: 'code' },
        { label: 'Diagnosis', fieldName: 'display' }
    ];

    chargeColumns = [
        { label: 'Code', fieldName: 'code' },
        { label: 'Service', fieldName: 'display' },
        { label: 'DOS', fieldName: 'serviceDate', type: 'date-local' },
        { label: 'Units', fieldName: 'units', type: 'number' },
        { label: 'Modifiers', fieldName: 'modifiers' },
        { label: 'Dx', fieldName: 'diagnosisPointers' },
        { label: 'Charge', fieldName: 'chargeAmount', type: 'currency' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Edit', name: EDIT },
                    { label: 'Delete', name: DELETE }
                ]
            }
        }
    ];

    @wire(getWorkspace, { encounterId: '$recordId' })
    wiredWorkspace({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.applyWorkspace(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.workspace = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    applyWorkspace(data) {
        this.workspace = data;
    }

    get hasSuperbill() {
        return Boolean(this.workspace?.superbill);
    }

    get superbillName() {
        return this.workspace?.superbill?.Name;
    }

    get status() {
        return this.workspace?.superbill?.Status__c;
    }

    get isReady() {
        return this.status === 'Ready';
    }

    get isLocked() {
        return ['Exported', 'Voided'].includes(this.status);
    }

    get isLockedOrSaving() {
        return this.isLocked || this.isSaving;
    }

    get cannotMarkReady() {
        return this.isSaving || this.isLocked || this.hasIssues;
    }

    get statusClass() {
        return this.isReady ? 'status status-ready' : 'status status-review';
    }

    get dateOfService() {
        return this.workspace?.superbill?.Date_of_Service__c;
    }

    get coverageName() {
        return this.workspace?.superbill?.Coverage__r?.Payer__r?.Name || 'Not selected';
    }

    get totalCharges() {
        return this.workspace?.totalCharges || 0;
    }

    get issues() {
        return this.workspace?.issues || [];
    }

    get hasIssues() {
        return this.issues.length > 0;
    }

    get diagnoses() {
        return (this.workspace?.diagnoses || []).map((row) => ({
            id: row.Id,
            sequence: row.Sequence__c,
            type: row.Diagnosis_Type__c,
            code: row.Diagnosis_Code__c,
            display: row.Diagnosis_Display__c
        }));
    }

    get hasDiagnoses() {
        return this.diagnoses.length > 0;
    }

    get charges() {
        return (this.workspace?.charges || []).map((row) => ({
            id: row.Id,
            codeReferenceId: row.Procedure_Ref__c,
            codeSystem: row.Procedure_Code_System__c,
            code: row.Procedure_Code__c,
            display: row.Procedure_Display__c,
            serviceDate: row.Service_Date__c,
            units: row.Units__c,
            chargeAmount: row.Charge_Amount__c,
            modifiers: row.Modifiers__c,
            diagnosisPointers: row.Diagnosis_Pointers__c
        }));
    }

    get hasCharges() {
        return this.charges.length > 0;
    }

    get chargeModalTitle() {
        return this.editingChargeId ? 'Edit charge' : 'Add charge';
    }

    emptyCharge() {
        return {
            serviceDate: this.dateOfService,
            units: 1,
            chargeAmount: null,
            modifiers: '',
            diagnosisPointers: '1',
            codeSystem: 'CPT',
            code: '',
            display: '',
            codeReferenceId: null
        };
    }

    async handleInitialize() {
        await this.runMutation(
            () => initializeSuperbill({ encounterId: this.recordId }),
            'Superbill synced from the encounter.'
        );
    }

    handleAddCharge() {
        this.editingChargeId = undefined;
        this.chargeDraft = this.emptyCharge();
        this.codeSearchValue = undefined;
        this.showChargeModal = true;
        this.errorMessage = undefined;
    }

    handleCloseCharge() {
        this.showChargeModal = false;
        this.editingChargeId = undefined;
        this.codeSearchValue = undefined;
        this.chargeDraft = this.emptyCharge();
    }

    handleCodeSelected(event) {
        this.chargeDraft = {
            ...this.chargeDraft,
            codeSystem: event.detail.system,
            code: event.detail.code,
            display: event.detail.display,
            codeReferenceId: event.detail.recordId
        };
        this.codeSearchValue = event.detail;
    }

    handleChargeField(event) {
        this.chargeDraft = { ...this.chargeDraft, [event.target.name]: event.detail.value };
    }

    async handleSaveCharge() {
        const inputs = [...this.template.querySelectorAll('lightning-input')];
        if (!inputs.reduce((valid, input) => input.reportValidity() && valid, true)) {
            return;
        }
        const input = {
            ...this.chargeDraft,
            chargeLineId: this.editingChargeId,
            superbillId: this.workspace.superbill.Id
        };
        const succeeded = await this.runMutation(() => saveCharge({ input }), 'Charge saved.');
        if (succeeded) {
            this.handleCloseCharge();
        }
    }

    async handleChargeAction(event) {
        const { action, row } = event.detail;
        if (action.name === EDIT) {
            this.editingChargeId = row.id;
            this.chargeDraft = {
                serviceDate: row.serviceDate,
                units: row.units,
                chargeAmount: row.chargeAmount,
                modifiers: row.modifiers || '',
                diagnosisPointers: row.diagnosisPointers || '',
                codeSystem: row.codeSystem,
                code: row.code,
                display: row.display,
                codeReferenceId: row.codeReferenceId
            };
            this.codeSearchValue = {
                system: row.codeSystem,
                code: row.code,
                display: row.display,
                recordId: row.codeReferenceId
            };
            this.showChargeModal = true;
            return;
        }
        if (action.name === DELETE) {
            const confirmed = await LightningConfirm.open({
                label: 'Delete charge',
                message: `Delete ${row.code || 'this charge'}?`,
                variant: 'headerless'
            });
            if (confirmed) {
                await this.runMutation(() => deleteCharge({ chargeLineId: row.id }), 'Charge deleted.');
            }
        }
    }

    async handleMarkReady() {
        await this.runMutation(
            () => markReady({ superbillId: this.workspace.superbill.Id }),
            'Superbill marked claim ready.'
        );
    }

    async handleReopen() {
        await this.runMutation(
            () => reopen({ superbillId: this.workspace.superbill.Id }),
            'Superbill reopened for review.'
        );
    }

    async runMutation(operation, successMessage) {
        if (this.isSaving) return false;
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const data = await operation();
            this.applyWorkspace(data);
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: successMessage, variant: 'success' }));
            this.dispatchEvent(new RefreshEvent());
            return true;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            return false;
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) return error.body.map((item) => item.message).join(', ');
        return error?.body?.message || error?.message || 'Unexpected error.';
    }
}
