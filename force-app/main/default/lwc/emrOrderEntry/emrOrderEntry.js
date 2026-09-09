import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import createServiceOrders from '@salesforce/apex/OrderEntryController.createServiceOrders';
import createMedicationOrders from '@salesforce/apex/OrderEntryController.createMedicationOrders';
import getEncounterOrders from '@salesforce/apex/OrderEntryController.getEncounterOrders';
import SERVICE_REQUEST_OBJECT from '@salesforce/schema/ServiceRequest__c';
import MEDICATION_REQUEST_OBJECT from '@salesforce/schema/MedicationRequest__c';

const TYPE_LAB = 'Lab';
const TYPE_IMAGING = 'Imaging';
const TYPE_REFERRAL = 'Referral';
const TYPE_PRESCRIPTION = 'Prescription';

export default class EmrOrderEntry extends LightningElement {
    @api recordId;

    orders = [];
    wiredOrdersResult;
    orderType = TYPE_LAB;
    codeSystem = 'LOINC';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    priority = 'Routine';
    reason = '';
    dosageText = '';
    doseQuantity = '';
    doseUnit = '';
    frequency = '';
    route = '';
    errorMessage;
    isSaving = false;
    showAddForm = false;

    typeOptions = [
        { label: 'Lab', value: TYPE_LAB },
        { label: 'Imaging', value: TYPE_IMAGING },
        { label: 'Referral', value: TYPE_REFERRAL },
        { label: 'Prescription', value: TYPE_PRESCRIPTION }
    ];

    priorityOptions = [
        { label: 'Routine', value: 'Routine' },
        { label: 'Urgent', value: 'Urgent' },
        { label: 'ASAP', value: 'ASAP' },
        { label: 'STAT', value: 'STAT' }
    ];

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

    get isPrescription() {
        return this.orderType === TYPE_PRESCRIPTION;
    }

    get isService() {
        return !this.isPrescription;
    }

    get codeSearchSystems() {
        return this.isPrescription ? ['RxNorm'] : ['CPT', 'LOINC'];
    }

    get codeSearchPlaceholder() {
        return this.isPrescription ? 'Search RxNorm' : 'Search CPT or LOINC';
    }

    get saveLabel() {
        return this.isPrescription ? 'Save prescription' : 'Save order';
    }

    get hasOrders() {
        return this.orders && this.orders.length > 0;
    }

    get showEmpty() {
        return !this.errorMessage && this.wiredOrdersResult?.data && !this.hasOrders;
    }

    get orderCards() {
        return (this.orders || []).map((row) => {
            const parts = [row.orderType, row.code, row.detail, row.status].filter((part) => part);
            return {
                id: row.id,
                title: row.display || 'Order',
                meta: parts.join(' · '),
                authoredOn: row.authoredOn,
                orderedBy: row.orderedBy,
                hasOrderInfo: !!(row.authoredOn || row.orderedBy),
                objectApiName: row.objectApiName
            };
        });
    }

    @wire(getEncounterOrders, { encounterId: '$recordId' })
    wiredOrders(result) {
        this.wiredOrdersResult = result;
        const { data, error } = result;
        if (data) {
            this.applyOrders(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.orders = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    applyOrders(data) {
        this.orders = (data || []).map((row) => ({
            ...row,
            objectApiName:
                row.objectApiName ||
                (row.orderType === TYPE_PRESCRIPTION
                    ? MEDICATION_REQUEST_OBJECT.objectApiName
                    : SERVICE_REQUEST_OBJECT.objectApiName)
        }));
    }

    handleOpenAdd() {
        this.showAddForm = true;
        this.errorMessage = undefined;
    }

    handleCloseAdd() {
        this.showAddForm = false;
        this.errorMessage = undefined;
        this.resetFormFields();
    }

    handleTypeChange(event) {
        this.orderType = event.detail.value;
        this.codeSystem = this.isPrescription ? 'RxNorm' : this.orderType === TYPE_LAB ? 'LOINC' : 'CPT';
        this.code = '';
        this.display = '';
        this.codeReferenceId = undefined;
        this.resetCodeSearch();
        this.priority = 'Routine';
        this.reason = '';
        this.dosageText = '';
        this.doseQuantity = '';
        this.doseUnit = '';
        this.frequency = '';
        this.route = '';
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

    handlePriorityChange(event) {
        this.priority = event.detail.value;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    handleDosageTextChange(event) {
        this.dosageText = event.detail.value;
    }

    handleDoseQuantityChange(event) {
        this.doseQuantity = event.detail.value;
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

    async handleSave() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        const savedPrescription = this.isPrescription;
        try {
            if (savedPrescription) {
                await createMedicationOrders({
                    encounterId: this.recordId,
                    inputs: [
                        {
                            codeSystem: this.codeSystem,
                            code: this.code,
                            display: this.display,
                            codeReferenceId: this.codeReferenceId,
                            dosageText: this.dosageText,
                            doseQuantity: this.toDecimal(this.doseQuantity),
                            doseUnit: this.doseUnit,
                            frequency: this.frequency,
                            route: this.route
                        }
                    ]
                });
            } else {
                await createServiceOrders({
                    encounterId: this.recordId,
                    inputs: [
                        {
                            category: this.orderType,
                            codeSystem: this.codeSystem,
                            code: this.code,
                            display: this.display,
                            codeReferenceId: this.codeReferenceId,
                            priority: this.priority,
                            reason: this.reason
                        }
                    ]
                });
            }
            this.resetFormFields();
            this.showAddForm = false;
            await refreshApex(this.wiredOrdersResult);
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Order saved',
                    message: savedPrescription
                        ? 'Prescription was created for this encounter.'
                        : 'Service request was created for this encounter.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    resetFormFields() {
        this.code = '';
        this.display = '';
        this.codeReferenceId = undefined;
        this.resetCodeSearch();
        this.reason = '';
        this.dosageText = '';
        this.doseQuantity = '';
        this.doseUnit = '';
        this.frequency = '';
        this.route = '';
        this.priority = 'Routine';
    }

    resetCodeSearch() {
        this.codeSearchValue = undefined;
        const picker = this.template.querySelector('c-emr-code-search');
        if (picker) {
            picker.clear();
        }
    }

    toDecimal(value) {
        if (value === '' || value === null || value === undefined) {
            return null;
        }
        const parsed = Number(value);
        return Number.isNaN(parsed) ? null : parsed;
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to save order.';
    }
}
