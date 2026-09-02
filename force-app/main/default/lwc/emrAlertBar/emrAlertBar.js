import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getActiveAllergies from '@salesforce/apex/AlertBarController.getActiveAllergies';
import DISPLAY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Display__c';
import CODE_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Code__c';
import CRITICALITY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Criticality__c';

const CRITICALITY_HIGH = 'High';

export default class EmrAlertBar extends LightningElement {
    @api recordId;

    allergies = [];
    errorMessage;
    hasLoaded = false;
    wiredAllergiesResult;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        if (!this.wiredAllergiesResult) {
            return Promise.resolve();
        }
        return refreshApex(this.wiredAllergiesResult);
    }

    @wire(getActiveAllergies, { recordId: '$recordId' })
    wiredAllergies(result) {
        this.wiredAllergiesResult = result;
        if (result.data) {
            this.allergies = result.data;
            this.errorMessage = undefined;
            this.hasLoaded = true;
        } else if (result.error) {
            this.allergies = [];
            this.errorMessage = this.reduceError(result.error);
            this.hasLoaded = true;
        }
    }

    get hasAllergies() {
        return this.allergies.length > 0;
    }

    get hasHighCriticality() {
        return this.allergies.some((row) => row[CRITICALITY_FIELD.fieldApiName] === CRITICALITY_HIGH);
    }

    get allergyItems() {
        return this.allergies.map((row) => {
            const criticality = row[CRITICALITY_FIELD.fieldApiName];
            const isHigh = criticality === CRITICALITY_HIGH;
            return {
                id: row.Id,
                name: row[DISPLAY_FIELD.fieldApiName] || row[CODE_FIELD.fieldApiName] || 'Allergy',
                criticality,
                isHigh,
                cssClass: isHigh ? 'allergy-chip allergy-chip_high' : 'allergy-chip'
            };
        });
    }

    get stripClass() {
        if (this.errorMessage) {
            return 'alert-strip alert-strip_error';
        }
        if (!this.hasAllergies) {
            return 'alert-strip alert-strip_empty';
        }
        if (this.hasHighCriticality) {
            return 'alert-strip alert-strip_high';
        }
        return 'alert-strip alert-strip_warning';
    }

    get stripRole() {
        return this.hasHighCriticality || this.errorMessage ? 'alert' : 'status';
    }

    get iconName() {
        if (this.errorMessage || this.hasHighCriticality) {
            return 'utility:error';
        }
        if (this.hasAllergies) {
            return 'utility:warning';
        }
        return '';
    }

    get iconVariant() {
        if (this.errorMessage || this.hasHighCriticality) {
            return 'error';
        }
        return 'warning';
    }

    get showIcon() {
        return !!this.iconName;
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load allergies.';
    }
}
