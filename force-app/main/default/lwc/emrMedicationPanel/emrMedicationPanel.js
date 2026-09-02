import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getMedications from '@salesforce/apex/MedicationPanelController.getMedications';
import addMedication from '@salesforce/apex/MedicationPanelController.addMedication';
import renewOrders from '@salesforce/apex/MedicationPanelController.renewOrders';
import discontinueOrders from '@salesforce/apex/MedicationPanelController.discontinueOrders';
import deleteOrders from '@salesforce/apex/MedicationPanelController.deleteOrders';
import deleteReportedMedications from '@salesforce/apex/MedicationPanelController.deleteReportedMedications';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import MEDICATION_REQUEST_OBJECT from '@salesforce/schema/MedicationRequest__c';
import MEDICATION_STATEMENT_OBJECT from '@salesforce/schema/MedicationStatement__c';
import DISPLAY_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Display__c';
import CODE_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/MedicationRequest__c.Medication_Code_System__c';
import STATUS_FIELD from '@salesforce/schema/MedicationRequest__c.Status__c';
import DOSAGE_FIELD from '@salesforce/schema/MedicationRequest__c.Dosage_Text__c';
import FREQUENCY_FIELD from '@salesforce/schema/MedicationRequest__c.Frequency__c';
import ROUTE_FIELD from '@salesforce/schema/MedicationRequest__c.Route__c';
import AUTHORED_FIELD from '@salesforce/schema/MedicationRequest__c.Authored_On__c';
import STATEMENT_DISPLAY_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Display__c';
import STATEMENT_CODE_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Code__c';
import STATEMENT_CODE_SYSTEM_FIELD from '@salesforce/schema/MedicationStatement__c.Medication_Code_System__c';
import STATEMENT_STATUS_FIELD from '@salesforce/schema/MedicationStatement__c.Status__c';
import STATEMENT_SOURCE_FIELD from '@salesforce/schema/MedicationStatement__c.Source__c';
import STATEMENT_DOSAGE_FIELD from '@salesforce/schema/MedicationStatement__c.Dosage_Text__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const RENEW = 'renew';
const DISCONTINUE = 'discontinue';
const DELETE = 'delete';
const DELETE_REPORTED = 'deleteReported';

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
    dosageText = '';
    doseQuantity;
    doseUnit = '';
    frequency = '';
    route = '';
    intent = 'Order';
    status = 'Active';
    requesterId;
    wiredMedicationsResult;

    routeOptions = [
        { label: 'Oral', value: 'Oral' },
        { label: 'Intravenous', value: 'Intravenous' },
        { label: 'Intramuscular', value: 'Intramuscular' },
        { label: 'Subcutaneous', value: 'Subcutaneous' },
        { label: 'Topical', value: 'Topical' },
        { label: 'Inhalation', value: 'Inhalation' },
        { label: 'Transdermal', value: 'Transdermal' },
        { label: 'Other', value: 'Other' }
    ];

    intentOptions = [
        { label: 'Order', value: 'Order' },
        { label: 'Plan', value: 'Plan' },
        { label: 'Proposal', value: 'Proposal' }
    ];

    statusOptions = [
        { label: 'Active', value: 'Active' },
        { label: 'On Hold', value: 'On Hold' },
        { label: 'Draft', value: 'Draft' },
        { label: 'Cancelled', value: 'Cancelled' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Stopped', value: 'Stopped' }
    ];

    get orderColumns() {
        return [
            urlColumn('Medication', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'System', fieldName: CODE_SYSTEM_FIELD.fieldApiName },
            { label: 'Dosage', fieldName: DOSAGE_FIELD.fieldApiName, wrapText: true },
            { label: 'Frequency', fieldName: FREQUENCY_FIELD.fieldApiName },
            { label: 'Route', fieldName: ROUTE_FIELD.fieldApiName },
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
                        { label: 'Discontinue', name: DISCONTINUE },
                        { label: 'Delete', name: DELETE }
                    ]
                }
            }
        ];
    }

    get reportedColumns() {
        return [
            urlColumn('Medication', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: STATEMENT_CODE_FIELD.fieldApiName },
            { label: 'System', fieldName: STATEMENT_CODE_SYSTEM_FIELD.fieldApiName },
            { label: 'Dosage', fieldName: STATEMENT_DOSAGE_FIELD.fieldApiName, wrapText: true },
            { label: 'Source', fieldName: STATEMENT_SOURCE_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATEMENT_STATUS_FIELD.fieldApiName },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Delete', name: DELETE_REPORTED }]
                }
            }
        ];
    }

    get medicationRequestObjectApiName() {
        return MEDICATION_REQUEST_OBJECT.objectApiName;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    get medicationStatementObjectApiName() {
        return MEDICATION_STATEMENT_OBJECT.objectApiName;
    }

    @wire(getMedications, { patientId: '$recordId' })
    wiredMedications(result) {
        this.wiredMedicationsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyMedications(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.activeOrders = [];
            this.reportedMedications = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyMedications(data) {
        const orders = data.activeOrders || [];
        const reported = data.reportedMedications || [];
        this.activeOrders = await withRecordUrls(
            this,
            orders,
            MEDICATION_REQUEST_OBJECT.objectApiName,
            { labelField: DISPLAY_FIELD.fieldApiName }
        );
        this.reportedMedications = await withRecordUrls(
            this,
            reported,
            MEDICATION_STATEMENT_OBJECT.objectApiName,
            { labelField: STATEMENT_DISPLAY_FIELD.fieldApiName }
        );
    }

    get hasActiveOrders() {
        return this.activeOrders.length > 0;
    }

    get hasReported() {
        return this.reportedMedications.length > 0;
    }

    get hasRecords() {
        return this.hasActiveOrders || this.hasReported;
    }

    get showEmpty() {
        return (
            !this.errorMessage &&
            this.wiredMedicationsResult?.data &&
            !this.hasActiveOrders &&
            !this.hasReported
        );
    }

    get activeOrderCards() {
        return (this.activeOrders || []).map((row) => {
            const parts = [
                row[CODE_FIELD.fieldApiName],
                row[DOSAGE_FIELD.fieldApiName],
                row[FREQUENCY_FIELD.fieldApiName],
                row[ROUTE_FIELD.fieldApiName],
                row[STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[DISPLAY_FIELD.fieldApiName] || 'Medication',
                meta: parts.join(' · '),
                objectApiName: MEDICATION_REQUEST_OBJECT.objectApiName
            };
        });
    }

    get reportedCards() {
        return (this.reportedMedications || []).map((row) => {
            const parts = [
                row[STATEMENT_CODE_FIELD.fieldApiName],
                row[STATEMENT_DOSAGE_FIELD.fieldApiName],
                row[STATEMENT_SOURCE_FIELD.fieldApiName],
                row[STATEMENT_STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[STATEMENT_DISPLAY_FIELD.fieldApiName] || 'Medication',
                meta: parts.join(' · '),
                objectApiName: MEDICATION_STATEMENT_OBJECT.objectApiName
            };
        });
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
        this.dosageText = '';
        this.doseQuantity = undefined;
        this.doseUnit = '';
        this.frequency = '';
        this.route = '';
        this.intent = 'Order';
        this.status = 'Active';
        this.requesterId = undefined;
    }

    handleDosageTextChange(event) {
        this.dosageText = event.detail.value;
    }

    handleDoseQuantityChange(event) {
        this.doseQuantity = event.detail.value === '' ? undefined : event.detail.value;
    }

    handleDoseUnitChange(event) {
        this.doseUnit = event.detail.value;
    }

    handleFrequencyChange(event) {
        this.frequency = event.detail.value;
    }

    handleRouteChange(event) {
        this.route = event.detail.value;
    }

    handleIntentChange(event) {
        this.intent = event.detail.value;
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleRequesterChange(event) {
        this.requesterId = event.detail.recordId;
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
                codeReferenceId: this.codeReferenceId,
                dosageText: this.dosageText,
                doseQuantity: this.doseQuantity || null,
                doseUnit: this.doseUnit,
                frequency: this.frequency,
                route: this.route || null,
                intent: this.intent,
                status: this.status,
                requesterId: this.requesterId || null
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredMedicationsResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleOrderCardAction(event) {
        this.handleRowAction({
            detail: {
                action: { name: event.currentTarget.dataset.action },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if (
            (actionName !== RENEW &&
                actionName !== DISCONTINUE &&
                actionName !== DELETE &&
                actionName !== DELETE_REPORTED) ||
            this.isSaving
        ) {
            return;
        }
        if (actionName === DELETE || actionName === DELETE_REPORTED) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this medication?',
                label: 'Delete medication',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const recordIds = [event.detail.row.Id];
            if (actionName === RENEW) {
                await renewOrders({ requestIds: recordIds });
            } else if (actionName === DISCONTINUE) {
                await discontinueOrders({ requestIds: recordIds });
            } else if (actionName === DELETE) {
                await deleteOrders({ requestIds: recordIds });
            } else {
                await deleteReportedMedications({ statementIds: recordIds });
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
