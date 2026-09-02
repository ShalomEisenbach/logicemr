import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getEncounters from '@salesforce/apex/EncounterPanelController.getEncounters';
import createEncounter from '@salesforce/apex/EncounterPanelController.createEncounter';
import deleteEncounters from '@salesforce/apex/EncounterPanelController.deleteEncounters';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import STATUS_FIELD from '@salesforce/schema/Encounter__c.Status__c';
import CLASS_FIELD from '@salesforce/schema/Encounter__c.Class__c';
import START_FIELD from '@salesforce/schema/Encounter__c.Start__c';
import PRACTITIONER_FIELD from '@salesforce/schema/Encounter__c.Practitioner__c';
import PRAC_FIRST_NAME_FIELD from '@salesforce/schema/Practitioner__c.First_Name__c';
import PRAC_LAST_NAME_FIELD from '@salesforce/schema/Practitioner__c.Last_Name__c';
import { urlColumn, withRecordUrls, recordViewPageRef } from 'c/emrNavigationUtils';

const OPEN_ENCOUNTER = 'open';
const DELETE = 'delete';
const STATUS_PLANNED = 'Planned';

export default class EmrEncounterPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    encounters;
    errorMessage;
    isSaving = false;
    showAddForm = false;
    encounterClass = '';
    status = STATUS_PLANNED;
    startValue;
    practitionerId;
    locationName = '';
    reason = '';
    wiredEncountersResult;

    classOptions = [
        { label: 'Inpatient', value: 'Inpatient' },
        { label: 'Outpatient', value: 'Outpatient' },
        { label: 'Emergency', value: 'Emergency' },
        { label: 'Virtual', value: 'Virtual' }
    ];

    statusOptions = [
        { label: 'Planned', value: 'Planned' },
        { label: 'Arrived', value: 'Arrived' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'Finished', value: 'Finished' },
        { label: 'Cancelled', value: 'Cancelled' }
    ];

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    get columns() {
        return [
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            { label: 'Class', fieldName: CLASS_FIELD.fieldApiName },
            urlColumn('Start', 'recordUrl', 'startLabel'),
            urlColumn('Attending', 'attendingUrl', 'attendingName'),
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Open', name: OPEN_ENCOUNTER },
                        { label: 'Delete', name: DELETE }
                    ]
                }
            }
        ];
    }

    @wire(getEncounters, { patientId: '$recordId' })
    wiredEncounters(result) {
        this.wiredEncountersResult = result;
        const { data, error } = result;
        if (data) {
            this.applyEncounters(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.encounters = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyEncounters(data) {
        const withNames = data.map((row) => {
            const start = row[START_FIELD.fieldApiName];
            return {
                ...row,
                attendingName: this.formatAttending(row),
                attendingId: row[PRACTITIONER_FIELD.fieldApiName],
                startLabel: start ? this.formatStartLabel(start) : 'Encounter'
            };
        });
        const withEncounterUrls = await withRecordUrls(
            this,
            withNames,
            ENCOUNTER_OBJECT.objectApiName,
            { labelField: 'startLabel', labelOutField: 'startLabel' }
        );
        this.encounters = await Promise.all(
            withEncounterUrls.map(async (row) => {
                let attendingUrl = '';
                if (row.attendingId) {
                    try {
                        attendingUrl = await this[NavigationMixin.GenerateUrl](
                            recordViewPageRef(row.attendingId, PRACTITIONER_OBJECT.objectApiName)
                        );
                    } catch (e) {
                        attendingUrl = '';
                    }
                }
                return { ...row, attendingUrl };
            })
        );
    }

    formatStartLabel(value) {
        try {
            const date = new Date(value);
            if (Number.isNaN(date.getTime())) {
                return String(value);
            }
            return date.toLocaleString(undefined, {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            });
        } catch (e) {
            return String(value);
        }
    }

    get hasEncounters() {
        return this.encounters && this.encounters.length > 0;
    }

    get showEmpty() {
        return this.encounters && this.encounters.length === 0 && !this.errorMessage;
    }

    get encounterCards() {
        return (this.encounters || []).map((row) => {
            const parts = [row[STATUS_FIELD.fieldApiName], row[CLASS_FIELD.fieldApiName], row.attendingName].filter(
                (part) => part
            );
            return {
                id: row.Id,
                title: parts[0] || 'Encounter',
                meta: parts.slice(1).join(' · '),
                objectApiName: ENCOUNTER_OBJECT.objectApiName
            };
        });
    }

    handleToggleAdd() {
        this.showAddForm = true;
        this.errorMessage = undefined;
        if (!this.startValue) {
            this.startValue = new Date().toISOString();
        }
    }

    handleCloseAdd() {
        this.showAddForm = false;
        this.errorMessage = undefined;
        this.resetAddForm();
    }

    resetAddForm() {
        this.encounterClass = '';
        this.status = STATUS_PLANNED;
        this.startValue = undefined;
        this.practitionerId = undefined;
        this.locationName = '';
        this.reason = '';
    }

    handleClassChange(event) {
        this.encounterClass = event.detail.value;
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleStartChange(event) {
        this.startValue = event.detail.value;
    }

    handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
    }

    handleLocationChange(event) {
        this.locationName = event.detail.value;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        if (!this.encounterClass) {
            this.errorMessage = 'Class is required.';
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await createEncounter({
                patientId: this.recordId,
                encounterClass: this.encounterClass,
                status: this.status,
                startTime: this.startValue || null,
                endTime: null,
                practitionerId: this.practitionerId || null,
                locationName: this.locationName,
                reason: this.reason
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredEncountersResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.encountersRelationshipApiName,
                actionName: 'view'
            }
        });
    }

    handleOpenCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: OPEN_ENCOUNTER },
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
        if (actionName === OPEN_ENCOUNTER) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: event.detail.row.Id,
                    objectApiName: ENCOUNTER_OBJECT.objectApiName,
                    actionName: 'view'
                }
            });
            return;
        }
        if (actionName !== DELETE || this.isSaving) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: 'Delete this encounter?',
            label: 'Delete encounter',
            theme: 'error'
        });
        if (!confirmed) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await deleteEncounters({ encounterIds: [event.detail.row.Id] });
            await refreshApex(this.wiredEncountersResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    get encountersRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Encounters__r` : 'Encounters__r';
    }

    formatAttending(row) {
        const relationshipName = PRACTITIONER_FIELD.fieldApiName.replace(/__c$/, '__r');
        const practitioner = row[relationshipName];
        if (!practitioner) {
            return '';
        }
        const first = practitioner[PRAC_FIRST_NAME_FIELD.fieldApiName] || '';
        const last = practitioner[PRAC_LAST_NAME_FIELD.fieldApiName] || '';
        return `${first} ${last}`.trim();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to update encounters.';
    }
}
