import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEvents from '@salesforce/apex/TimelineController.getEvents';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import CONDITION_OBJECT from '@salesforce/schema/Condition__c';
import OBSERVATION_OBJECT from '@salesforce/schema/Observation__c';
import MEDICATION_REQUEST_OBJECT from '@salesforce/schema/MedicationRequest__c';
import PROCEDURE_OBJECT from '@salesforce/schema/Procedure__c';

const TYPE_META = {
    Encounter: {
        label: 'Encounters',
        shortLabel: 'Enc',
        typeLabel: 'Encounter',
        iconName: 'standard:event',
        iconClass: 'timeline-icon timeline-icon_encounter'
    },
    Condition: {
        label: 'Conditions',
        shortLabel: 'Cond',
        typeLabel: 'Condition',
        iconName: 'standard:first_non_empty',
        iconClass: 'timeline-icon timeline-icon_condition'
    },
    Observation: {
        label: 'Observations',
        shortLabel: 'Obs',
        typeLabel: 'Observation',
        iconName: 'standard:metrics',
        iconClass: 'timeline-icon timeline-icon_observation'
    },
    MedicationRequest: {
        label: 'Medications',
        shortLabel: 'Meds',
        typeLabel: 'Medication',
        iconName: 'standard:product',
        iconClass: 'timeline-icon timeline-icon_medication'
    },
    Procedure: {
        label: 'Procedures',
        shortLabel: 'Proc',
        typeLabel: 'Procedure',
        iconName: 'standard:procedure',
        iconClass: 'timeline-icon timeline-icon_procedure'
    }
};

const OBJECT_BY_TYPE = {
    Encounter: ENCOUNTER_OBJECT,
    Condition: CONDITION_OBJECT,
    Observation: OBSERVATION_OBJECT,
    MedicationRequest: MEDICATION_REQUEST_OBJECT,
    Procedure: PROCEDURE_OBJECT
};

export default class EmrClinicalTimeline extends NavigationMixin(LightningElement) {
    @api recordId;

    events;
    errorMessage;
    enabledTypes = {
        Encounter: true,
        Condition: true,
        Observation: true,
        MedicationRequest: true,
        Procedure: true
    };

    @wire(getEvents, { patientId: '$recordId' })
    wiredEvents({ data, error }) {
        if (data) {
            this.events = data.map((row) => this.toViewEvent(row));
            this.errorMessage = undefined;
        } else if (error) {
            this.events = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get filterChips() {
        return Object.keys(TYPE_META).map((type) => {
            const enabled = this.enabledTypes[type];
            return {
                type,
                label: TYPE_META[type].label,
                shortLabel: TYPE_META[type].shortLabel,
                pressed: enabled ? 'true' : 'false',
                className: enabled ? 'filter-chip filter-chip_on' : 'filter-chip'
            };
        });
    }

    get visibleEvents() {
        return (this.events || []).filter((event) => this.enabledTypes[event.type]);
    }

    get hasEvents() {
        return this.visibleEvents.length > 0;
    }

    get showEmpty() {
        return Array.isArray(this.events) && !this.errorMessage && this.visibleEvents.length === 0;
    }

    get emptyMessage() {
        if (!this.events || this.events.length === 0) {
            return 'No clinical events.';
        }
        return 'No clinical events match the selected filters.';
    }

    handleFilterClick(event) {
        const type = event.currentTarget.dataset.type;
        if (!type) {
            return;
        }
        this.enabledTypes = {
            ...this.enabledTypes,
            [type]: !this.enabledTypes[type]
        };
    }

    handleEventClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const type = event.currentTarget.dataset.type;
        const objectInfo = OBJECT_BY_TYPE[type];
        if (!recordId || !objectInfo) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: objectInfo.objectApiName,
                actionName: 'view'
            }
        });
    }

    handleEventKeydown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        event.preventDefault();
        this.handleEventClick(event);
    }

    toViewEvent(row) {
        const meta = TYPE_META[row.type] || TYPE_META.Encounter;
        const dateTime = this.normalizeDateTime(row.eventDateTime);
        return {
            type: row.type,
            dateTime,
            title: row.title,
            subtitle: row.subtitle,
            recordId: row.recordId,
            typeLabel: meta.typeLabel,
            iconName: meta.iconName,
            iconClass: meta.iconClass,
            hasDateTime: dateTime != null
        };
    }

    /**
     * Apex serializes Datetime as 2024-03-15T10:00:00.000+0000.
     * lightning-relative-date-time needs ISO 8601 (+00:00 or Z) or a timestamp.
     */
    normalizeDateTime(value) {
        if (value == null || value === '') {
            return null;
        }
        if (value instanceof Date) {
            return Number.isNaN(value.getTime()) ? null : value.getTime();
        }
        if (typeof value === 'number') {
            return Number.isNaN(value) ? null : value;
        }
        const iso = String(value).replace(/([+-]\d{2})(\d{2})$/, '$1:$2');
        const parsed = new Date(iso);
        return Number.isNaN(parsed.getTime()) ? null : parsed.getTime();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load clinical timeline.';
    }
}
