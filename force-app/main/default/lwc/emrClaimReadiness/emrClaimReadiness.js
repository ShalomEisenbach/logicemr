import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getWorkspace from '@salesforce/apex/ClaimReadinessController.getWorkspace';
import initializeSuperbill from '@salesforce/apex/ClaimReadinessController.initializeSuperbill';
import refreshClaimSnapshots from '@salesforce/apex/ClaimReadinessController.refreshClaimSnapshots';
import updateClaimDetails from '@salesforce/apex/ClaimReadinessController.updateClaimDetails';
import saveCharge from '@salesforce/apex/ClaimReadinessController.saveCharge';
import deleteCharge from '@salesforce/apex/ClaimReadinessController.deleteCharge';
import markReady from '@salesforce/apex/ClaimReadinessController.markReady';
import reopen from '@salesforce/apex/ClaimReadinessController.reopen';
import quoteRate from '@salesforce/apex/ClaimReadinessController.quoteRate';
import getCanonicalJson from '@salesforce/apex/ClaimExportController.getCanonicalJson';

const EDIT = 'edit';
const DELETE = 'delete';

export default class EmrClaimReadiness extends LightningElement {
    @api recordId;

    workspace;
    errorMessage;
    isLoading = true;
    isSaving = false;
    showChargeModal = false;
    showExportModal = false;
    exportJson = '';
    editingChargeId;
    codeSearchValue;
    rateMessage;
    quoteSequence = 0;
    codeSystems = ['CPT', 'HCPCS'];
    placeOfServiceOptions = [
        { label: '02 - Telehealth (not home)', value: '02' },
        { label: '10 - Telehealth (home)', value: '10' },
        { label: '11 - Office', value: '11' },
        { label: '12 - Home', value: '12' },
        { label: '21 - Inpatient Hospital', value: '21' },
        { label: '22 - Outpatient Hospital', value: '22' },
        { label: '23 - Emergency Room', value: '23' },
        { label: '24 - Ambulatory Surgical Center', value: '24' },
        { label: '31 - Skilled Nursing Facility', value: '31' },
        { label: '32 - Nursing Facility', value: '32' },
        { label: '49 - Independent Clinic', value: '49' },
        { label: '50 - Federally Qualified Health Center', value: '50' },
        { label: '53 - Community Mental Health Center', value: '53' },
        { label: '71 - Public Health Clinic', value: '71' },
        { label: '72 - Rural Health Clinic', value: '72' },
        { label: '81 - Independent Laboratory', value: '81' },
        { label: '99 - Other', value: '99' }
    ];
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
        { label: 'Rate source', fieldName: 'rateSource', wrapText: true },
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

    get superbillId() {
        return this.workspace?.superbill?.Id;
    }

    get status() {
        return this.workspace?.superbill?.Status__c;
    }

    get isReady() {
        return this.status === 'Ready';
    }

    get isExported() {
        return this.status === 'Exported';
    }

    get canPreviewExport() {
        return this.isReady || this.isExported;
    }

    get showSubmissionPanel() {
        return this.isReady || this.isExported;
    }

    get isLocked() {
        return ['Ready', 'Exported', 'Voided'].includes(this.status);
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

    get placeOfServiceCode() {
        return this.workspace?.superbill?.Place_of_Service_Code__c;
    }

    get coverageName() {
        return this.workspace?.superbill?.Payer_Name__c || 'Not selected';
    }

    get totalCharges() {
        return this.workspace?.totalCharges || 0;
    }

    get canOverrideRates() {
        return Boolean(this.workspace?.canOverrideRates);
    }

    get snapshotVersion() {
        return this.workspace?.superbill?.Snapshot_Version__c || 'Not captured';
    }

    get snapshotRefreshedAt() {
        return this.workspace?.superbill?.Snapshot_Refreshed_At__c;
    }

    get subscriberName() {
        const snapshot = this.workspace?.superbill;
        return [snapshot?.Subscriber_First_Name__c, snapshot?.Subscriber_Last_Name__c]
            .filter(Boolean)
            .join(' ') || 'Missing';
    }

    get patientName() {
        const snapshot = this.workspace?.superbill;
        return [snapshot?.Patient_First_Name__c, snapshot?.Patient_Last_Name__c]
            .filter(Boolean)
            .join(' ') || 'Missing';
    }

    get patientDetails() {
        const snapshot = this.workspace?.superbill;
        return `${snapshot?.Patient_Date_of_Birth__c || 'DOB missing'} · ${snapshot?.Patient_Sex__c || 'sex missing'}`;
    }

    get subscriberDetails() {
        const snapshot = this.workspace?.superbill;
        const relationship = snapshot?.Subscriber_Relationship__c || 'relationship missing';
        const memberId = snapshot?.Subscriber_Member_Id__c || 'member ID missing';
        const group = snapshot?.Subscriber_Group_Number__c ? ` · Group ${snapshot.Subscriber_Group_Number__c}` : '';
        return `${relationship} · Member ${memberId}${group}`;
    }

    get subscriberDateOfBirth() {
        return this.workspace?.superbill?.Subscriber_Date_of_Birth__c;
    }

    get subscriberSex() {
        return this.workspace?.superbill?.Subscriber_Sex__c || 'sex missing';
    }

    get payerSnapshot() {
        const snapshot = this.workspace?.superbill;
        return `${snapshot?.Payer_Name__c || 'Missing'} · ${snapshot?.Payer_Identifier__c || 'payer ID missing'} · Filing ${snapshot?.Claim_Filing_Code__c || 'missing'}`;
    }

    get renderingProviderSnapshot() {
        const snapshot = this.workspace?.superbill;
        return `${snapshot?.Rendering_Provider_Name__c || 'Missing'} · NPI ${snapshot?.Rendering_Provider_NPI__c || 'missing'} · ${snapshot?.Rendering_Provider_Taxonomy__c || 'taxonomy missing'}`;
    }

    get billingProviderSnapshot() {
        const snapshot = this.workspace?.superbill;
        return `${snapshot?.Billing_Provider_Name__c || 'Missing'} · NPI ${snapshot?.Billing_Provider_NPI__c || 'missing'} · EIN ${snapshot?.Billing_Provider_EIN__c || 'missing'} · ${snapshot?.Billing_Provider_Taxonomy__c || 'taxonomy missing'}`;
    }

    get billingProviderAddress() {
        const snapshot = this.workspace?.superbill;
        return [
            snapshot?.Billing_Provider_Street__c,
            snapshot?.Billing_Provider_City__c,
            snapshot?.Billing_Provider_State__c,
            snapshot?.Billing_Provider_Postal_Code__c
        ].filter(Boolean).join(', ') || 'Address missing';
    }

    get isChargeAmountDisabled() {
        return !this.chargeDraft.rateOverride;
    }

    get isChargeAmountRequired() {
        return this.chargeDraft.rateOverride;
    }

    get showOverrideReason() {
        return this.canOverrideRates && this.chargeDraft.rateOverride;
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
            diagnosisPointers: row.Diagnosis_Pointers__c,
            rateOverride: Boolean(row.Rate_Override__c),
            overrideReason: row.Override_Reason__c,
            rateSource: row.Rate_Override__c
                ? `${row.Rate_Source__c || 'Manual rate'} - override: ${row.Override_Reason__c || 'reason missing'}`
                : row.Rate_Source__c || 'Missing'
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
            rateOverride: false,
            overrideReason: '',
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

    async handleRefreshSnapshots() {
        const confirmed = await LightningConfirm.open({
            label: 'Refresh claim snapshots',
            message: 'Replace the subscriber and provider snapshots with current source record values?',
            variant: 'header'
        });
        if (!confirmed) return;
        await this.runMutation(
            () => refreshClaimSnapshots({ superbillId: this.workspace.superbill.Id }),
            'Subscriber and provider snapshots refreshed.'
        );
    }

    async handlePlaceOfServiceChange(event) {
        await this.runMutation(
            () => updateClaimDetails({
                superbillId: this.workspace.superbill.Id,
                placeOfServiceCode: event.detail.value
            }),
            'Place of service updated.'
        );
    }

    handleAddCharge() {
        this.quoteSequence += 1;
        this.editingChargeId = undefined;
        this.chargeDraft = this.emptyCharge();
        this.codeSearchValue = undefined;
        this.rateMessage = undefined;
        this.showChargeModal = true;
        this.errorMessage = undefined;
    }

    handleCloseCharge() {
        this.quoteSequence += 1;
        this.showChargeModal = false;
        this.editingChargeId = undefined;
        this.codeSearchValue = undefined;
        this.rateMessage = undefined;
        this.chargeDraft = this.emptyCharge();
    }

    async handleCodeSelected(event) {
        this.chargeDraft = {
            ...this.chargeDraft,
            codeSystem: event.detail.system,
            code: event.detail.code,
            display: event.detail.display,
            codeReferenceId: event.detail.recordId
        };
        this.codeSearchValue = event.detail;
        await this.refreshRateQuote();
    }

    async handleChargeField(event) {
        const { name, type, checked } = event.target;
        const value = type === 'checkbox' ? checked : event.detail.value;
        this.chargeDraft = { ...this.chargeDraft, [name]: value };
        if (name === 'rateOverride') {
            if (!value) {
                this.chargeDraft = { ...this.chargeDraft, overrideReason: '' };
                await this.refreshRateQuote();
            }
            return;
        }
        if (['serviceDate', 'units'].includes(name)) {
            await this.refreshRateQuote();
        }
    }

    async refreshRateQuote() {
        if (
            this.chargeDraft.rateOverride ||
            !this.workspace?.superbill?.Id ||
            !this.chargeDraft.codeSystem ||
            !this.chargeDraft.code ||
            !this.chargeDraft.serviceDate ||
            !this.chargeDraft.units
        ) {
            return;
        }
        const sequence = ++this.quoteSequence;
        try {
            const quote = await quoteRate({
                superbillId: this.workspace.superbill.Id,
                codeSystem: this.chargeDraft.codeSystem,
                code: this.chargeDraft.code,
                serviceDate: this.chargeDraft.serviceDate,
                units: this.chargeDraft.units
            });
            if (sequence !== this.quoteSequence || this.chargeDraft.rateOverride) return;
            this.chargeDraft = {
                ...this.chargeDraft,
                chargeAmount: quote?.found ? quote.lineAmount : null
            };
            this.rateMessage = quote?.found ? `Calculated from ${quote.source}.` : quote?.message;
        } catch (error) {
            if (sequence === this.quoteSequence) {
                this.rateMessage = this.reduceError(error);
            }
        }
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
                rateOverride: row.rateOverride,
                overrideReason: row.overrideReason || '',
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
            this.rateMessage = row.rateSource;
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

    async handlePreviewExport() {
        if (this.isSaving) return;
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            this.exportJson = await getCanonicalJson({ superbillId: this.workspace.superbill.Id });
            this.showExportModal = true;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleCloseExport() {
        this.showExportModal = false;
        this.exportJson = '';
    }

    async runMutation(operation, successMessage) {
        if (this.isSaving) return false;
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const data = await operation();
            this.applyWorkspace(data);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                })
            );
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
