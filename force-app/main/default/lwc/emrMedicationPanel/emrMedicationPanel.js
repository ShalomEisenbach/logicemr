import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import getMedications from '@salesforce/apex/MedicationPanelController.getMedications';
import addMedication from '@salesforce/apex/MedicationPanelController.addMedication';
import renewOrders from '@salesforce/apex/MedicationPanelController.renewOrders';
import discontinueOrders from '@salesforce/apex/MedicationPanelController.discontinueOrders';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import DISPLAY_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Display__c';
import CODE_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Code_System__c';
import STATUS_FIELD from '@salesforce/schema/MedicationRequest__c.Status__c';
import DOSAGE_FIELD from '@salesforce/schema/MedicationRequest__c.Dosage_Text__c';
import AUTHORED_FIELD from '@salesforce/schema/MedicationRequest__c.Authored_On__c';
import STATEMENT_DISPLAY_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Display__c';
import STATEMENT_CODE_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Code__c';
import STATEMENT_CODE_SYSTEM_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Code_System__c';
import STATEMENT_STATUS_FIELD from '@salesforce/schema/MedicationStatement__c.Status__c';
import STATEMENT_SOURCE_FIELD from '@salesforce/schema/MedicationStatement__c.Source__c';
import STATEMENT_DOSAGE_FIELD from '@salesforce/schema/MedicationStatement__c.Dosage_Text__c';

const RENEW = 'renew';
const DISCONTINUE = 'discontinue';

export default class EmrMedicationPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    activeOrders = [];
    reportedMedications = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'RxNorm';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['RxNorm'];
    wiredMedicationsResult;

    orderColumns = [
        { label: 'Medication', fieldName: DISPLAY_FIELD.fieldApiName, wrapText: true },
        { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
        { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
        { label: 'Dosage', fieldName: DOSAGE_FIELD.fieldApiName, wrapText: true },
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
        {
            label: 'Authored',
            fieldName: AUTHORED_FIELD.fieldApiName,
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit'
            }
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Renew', name: RENEW },
                    { label: 'Discontinue', name: DISCONTINUE }
                ]
            }
        }
    ];

    reportedColumns = [
        { label: 'Medication', fieldName: STATEMENT_DISPLAY_FIELD.fieldApiName, wrapText: true },
        { label: 'Code', fieldName: STATEMENT_CODE_FIELD.fieldApiName },
        { label: 'System', fieldName: STATEMENT_CODE_SYSTEM_FIELD.fieldApiName },
        { label: 'Dosage', fieldName: STATEMENT_DOSAGE_FIELD.fieldApiName, wrapText: true },
        { label: 'Source', fieldName: STATEMENT_SOURCE_FIELD.fieldApiName },
        { label: 'Status', fieldName: STATEMENT_STATUS_FIELD.fieldApiName }
    ];

    @wire(getMedications, { patientId: '$recordId' })
    wiredMedications(result) {
        this.wiredMedicationsResult = result;
        const { data, error } = result;
        if (data) {
            this.activeOrders = data.activeOrders || [];
            this.reportedMedications = data.reportedMedications || [];
            this.errorMessage = undefined;
        } else if (error) {
            this.activeOrders = [];
            this.reportedMedications = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasActiveOrders() {
        return this.activeOrders.length > 0;
    }

    get hasReported() {
        return this.reportedMedications.length > 0;
    }

    get showEmpty() {
        return (
            !this.errorMessage &&
            this.wiredMedicationsResult?.data &&
            !this.hasActiveOrders &&
            !this.hasReported
        );
    }

    get medicationRequestsRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__MedicationRequests__r` : 'MedicationRequests__r';
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.medicationRequestsRelationshipApiName,
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
            await addMedication({
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
            await refreshApex(this.wiredMedicationsResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if ((actionName !== RENEW && actionName !== DISCONTINUE) || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const requestIds = [event.detail.row.Id];
            if (actionName === RENEW) {
                await renewOrders({ requestIds });
            } else {
                await discontinueOrders({ requestIds });
            }
            await refreshApex(this.wiredMedicationsResult);
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
        return error?.message || 'Unable to update medications.';
    }
}
