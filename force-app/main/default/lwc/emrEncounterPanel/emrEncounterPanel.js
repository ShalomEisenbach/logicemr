import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEncounters from '@salesforce/apex/EncounterPanelController.getEncounters';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import STATUS_FIELD from '@salesforce/schema/Encounter__c.Status__c';
import CLASS_FIELD from '@salesforce/schema/Encounter__c.Class__c';
import START_FIELD from '@salesforce/schema/Encounter__c.Start__c';
import PRACTITIONER_FIELD from '@salesforce/schema/Encounter__c.Practitioner__c';
import PRAC_FIRST_NAME_FIELD from '@salesforce/schema/Practitioner__c.First_Name__c';
import PRAC_LAST_NAME_FIELD from '@salesforce/schema/Practitioner__c.Last_Name__c';

const OPEN_ENCOUNTER = 'open';

export default class EmrEncounterPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    encounters;
    errorMessage;

    columns = [
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
        { label: 'Class', fieldName: CLASS_FIELD.fieldApiName },
        {
            label: 'Start',
            fieldName: START_FIELD.fieldApiName,
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        { label: 'Attending', fieldName: 'attendingName' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Open', name: OPEN_ENCOUNTER }]
            }
        }
    ];

    @wire(getEncounters, { patientId: '$recordId' })
    wiredEncounters({ data, error }) {
        if (data) {
            this.encounters = data.map((row) => ({
                ...row,
                attendingName: this.formatAttending(row)
            }));
            this.errorMessage = undefined;
        } else if (error) {
            this.encounters = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasEncounters() {
        return this.encounters && this.encounters.length > 0;
    }

    get showEmpty() {
        return this.encounters && this.encounters.length === 0 && !this.errorMessage;
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

    handleRowAction(event) {
        if (event.detail.action.name !== OPEN_ENCOUNTER) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.row.Id,
                objectApiName: ENCOUNTER_OBJECT.objectApiName,
                actionName: 'view'
            }
        });
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
        return error?.message || 'Unable to load encounters.';
    }
}
