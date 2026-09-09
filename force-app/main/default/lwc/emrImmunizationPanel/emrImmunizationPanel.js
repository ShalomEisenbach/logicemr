import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getImmunizations from '@salesforce/apex/ImmunizationPanelController.getImmunizations';
import addImmunization from '@salesforce/apex/ImmunizationPanelController.addImmunization';
import markEnteredInError from '@salesforce/apex/ImmunizationPanelController.markEnteredInError';
import deleteImmunizations from '@salesforce/apex/ImmunizationPanelController.deleteImmunizations';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import IMMUNIZATION_OBJECT from '@salesforce/schema/Immunization__c';
import DISPLAY_FIELD from '@salesforce/schema/Immunization__c.Vaccine_Display__c';
import CODE_FIELD from '@salesforce/schema/Immunization__c.Vaccine_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/Immunization__c.Vaccine_Code_System__c';
import STATUS_FIELD from '@salesforce/schema/Immunization__c.Status__c';
import OCCURRENCE_FIELD from '@salesforce/schema/Immunization__c.Occurrence_Date__c';
import LOT_FIELD from '@salesforce/schema/Immunization__c.Lot_Number__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const ENTERED_IN_ERROR = 'enteredInError';
const DELETE = 'delete';
const STATUS_ENTERED_IN_ERROR = 'Entered in Error';

function todayIsoDate() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${now.getFullYear()}-${month}-${day}`;
}

export default class EmrImmunizationPanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api contextObjectApiName;

    immunizations = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'CVX';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['CVX', 'SNOMED'];
    status = 'Completed';
    occurrenceDate = todayIsoDate();
    lotNumber = '';
    performerId;
    wiredImmunizationsResult;
    refreshHandlerId;

    statusOptions = [
        { label: 'Completed', value: 'Completed' },
        { label: 'Not Done', value: 'Not Done' },
        { label: 'Entered in Error', value: 'Entered in Error' }
    ];

    get columns() {
        return [
            urlColumn('Vaccine', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            {
                label: 'Occurrence',
                fieldName: OCCURRENCE_FIELD.fieldApiName,
                type: 'date-local',
                typeAttributes: {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit'
                }
            },
            { label: 'Lot', fieldName: LOT_FIELD.fieldApiName },
            { label: 'Performer', fieldName: 'performerName' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: this.getRowActions.bind(this)
                }
            }
        ];
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.handleRefresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshHandlerId) {
            unregisterRefreshHandler(this.refreshHandlerId);
        }
    }

    async handleRefresh() {
        await refreshApex(this.wiredImmunizationsResult);
        return true;
    }

    @wire(getImmunizations, { recordId: '$recordId' })
    wiredImmunizations(result) {
        this.wiredImmunizationsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyImmunizations(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.immunizations = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyImmunizations(data) {
        const withUrls = await withRecordUrls(this, data, IMMUNIZATION_OBJECT.objectApiName, {
            labelField: DISPLAY_FIELD.fieldApiName
        });
        this.immunizations = withUrls.map((row) => ({
            ...row,
            performerName: row.Performer__r ? row.Performer__r.Name : ''
        }));
    }

    get hasImmunizations() {
        return this.immunizations && this.immunizations.length > 0;
    }

    get showEmpty() {
        return this.immunizations && this.immunizations.length === 0 && !this.errorMessage;
    }

    get immunizationCards() {
        return (this.immunizations || []).map((row) => {
            const status = row[STATUS_FIELD.fieldApiName];
            const parts = [
                row[CODE_FIELD.fieldApiName],
                row[CODE_SYSTEM_FIELD.fieldApiName],
                status,
                row[LOT_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[DISPLAY_FIELD.fieldApiName] || 'Immunization',
                meta: parts.join(' · '),
                occurrenceDate: row[OCCURRENCE_FIELD.fieldApiName],
                performerName: row.performerName,
                canMarkError: status !== STATUS_ENTERED_IN_ERROR,
                objectApiName: IMMUNIZATION_OBJECT.objectApiName
            };
        });
    }

    get isEncounterContext() {
        return this.contextObjectApiName === ENCOUNTER_OBJECT.objectApiName;
    }

    get immunizationsRelationshipApiName() {
        const hostObject = this.isEncounterContext
            ? ENCOUNTER_OBJECT.objectApiName
            : PATIENT_OBJECT.objectApiName;
        const parts = hostObject.split('__');
        return parts.length === 3 ? `${parts[0]}__Immunizations__r` : 'Immunizations__r';
    }

    get hostObjectApiName() {
        return this.isEncounterContext ? ENCOUNTER_OBJECT.objectApiName : PATIENT_OBJECT.objectApiName;
    }

    getRowActions(row, doneCallback) {
        const actions = [];
        if (row[STATUS_FIELD.fieldApiName] !== STATUS_ENTERED_IN_ERROR) {
            actions.push({ label: 'Entered in Error', name: ENTERED_IN_ERROR });
        }
        actions.push({ label: 'Delete', name: DELETE });
        doneCallback(actions);
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: this.hostObjectApiName,
                relationshipApiName: this.immunizationsRelationshipApiName,
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
        this.codeSystem = 'CVX';
        this.code = '';
        this.display = '';
        this.codeReferenceId = undefined;
        this.codeSearchValue = undefined;
        this.status = 'Completed';
        this.occurrenceDate = todayIsoDate();
        this.lotNumber = '';
        this.performerId = undefined;
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

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleOccurrenceChange(event) {
        this.occurrenceDate = event.detail.value || null;
    }

    handleLotChange(event) {
        this.lotNumber = event.detail.value;
    }

    handlePerformerChange(event) {
        this.performerId = event.detail.recordId;
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addImmunization({
                recordId: this.recordId,
                codeSystem: this.codeSystem,
                code: this.code,
                display: this.display,
                codeReferenceId: this.codeReferenceId,
                occurrenceDate: this.occurrenceDate || null,
                lotNumber: this.lotNumber,
                status: this.status,
                performerId: this.performerId
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredImmunizationsResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleEnteredInErrorCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: ENTERED_IN_ERROR },
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
        if ((actionName !== ENTERED_IN_ERROR && actionName !== DELETE) || this.isSaving) {
            return;
        }
        if (actionName === DELETE) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this immunization?',
                label: 'Delete immunization',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const immunizationIds = [event.detail.row.Id];
            if (actionName === ENTERED_IN_ERROR) {
                await markEnteredInError({ immunizationIds });
            } else {
                await deleteImmunizations({ immunizationIds });
            }
            await refreshApex(this.wiredImmunizationsResult);
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
        return error?.message || 'Unable to update immunizations.';
    }
}
