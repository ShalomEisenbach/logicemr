import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import getAllergies from '@salesforce/apex/AllergyPanelController.getAllergies';
import addAllergy from '@salesforce/apex/AllergyPanelController.addAllergy';
import inactivateAllergies from '@salesforce/apex/AllergyPanelController.inactivateAllergies';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import DISPLAY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Display__c';
import TYPE_FIELD from '@salesforce/schema/AllergyIntolerance__c.Type__c';
import CATEGORY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Category__c';
import CRITICALITY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Criticality__c';
import REACTION_FIELD from '@salesforce/schema/AllergyIntolerance__c.Reaction__c';
import STATUS_FIELD from '@salesforce/schema/AllergyIntolerance__c.Clinical_Status__c';

const INACTIVATE = 'inactivate';

export default class EmrAllergyPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    allergies = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'RxNorm';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['RxNorm', 'SNOMED'];
    allergyType = 'Allergy';
    category = 'Medication';
    criticality = '';
    reaction = '';
    wiredAllergiesResult;

    typeOptions = [
        { label: 'Allergy', value: 'Allergy' },
        { label: 'Intolerance', value: 'Intolerance' }
    ];

    categoryOptions = [
        { label: 'Medication', value: 'Medication' },
        { label: 'Food', value: 'Food' },
        { label: 'Environment', value: 'Environment' },
        { label: 'Biologic', value: 'Biologic' }
    ];

    criticalityOptions = [
        { label: 'Low', value: 'Low' },
        { label: 'High', value: 'High' },
        { label: 'Unable to Assess', value: 'Unable to Assess' }
    ];

    columns = [
        { label: 'Allergen', fieldName: DISPLAY_FIELD.fieldApiName, wrapText: true },
        { label: 'Type', fieldName: TYPE_FIELD.fieldApiName },
        { label: 'Category', fieldName: CATEGORY_FIELD.fieldApiName },
        { label: 'Criticality', fieldName: CRITICALITY_FIELD.fieldApiName },
        { label: 'Reaction', fieldName: REACTION_FIELD.fieldApiName, wrapText: true },
        { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
        {
            type: 'action',
            typeAttributes: {
                rowActions: this.getRowActions.bind(this)
            }
        }
    ];

    @wire(getAllergies, { patientId: '$recordId' })
    wiredAllergies(result) {
        this.wiredAllergiesResult = result;
        const { data, error } = result;
        if (data) {
            this.allergies = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.allergies = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasAllergies() {
        return this.allergies && this.allergies.length > 0;
    }

    get showEmpty() {
        return this.allergies && this.allergies.length === 0 && !this.errorMessage;
    }

    get allergiesRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Allergies__r` : 'Allergies__r';
    }

    getRowActions(row, doneCallback) {
        const actions = [];
        if (row[STATUS_FIELD.fieldApiName] === 'Active') {
            actions.push({ label: 'Inactivate', name: INACTIVATE });
        }
        doneCallback(actions);
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.allergiesRelationshipApiName,
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

    handleTypeChange(event) {
        this.allergyType = event.detail.value;
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleCriticalityChange(event) {
        this.criticality = event.detail.value;
    }

    handleReactionChange(event) {
        this.reaction = event.detail.value;
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addAllergy({
                patientId: this.recordId,
                codeSystem: this.codeSystem,
                code: this.code,
                display: this.display,
                codeReferenceId: this.codeReferenceId,
                allergyType: this.allergyType,
                category: this.category,
                criticality: this.criticality,
                reaction: this.reaction
            });
            this.code = '';
            this.display = '';
            this.codeReferenceId = undefined;
            this.codeSearchValue = undefined;
            this.reaction = '';
            this.showAddForm = false;
            await refreshApex(this.wiredAllergiesResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRowAction(event) {
        if (event.detail.action.name !== INACTIVATE || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await inactivateAllergies({ allergyIds: [event.detail.row.Id] });
            await refreshApex(this.wiredAllergiesResult);
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
        return error?.message || 'Unable to update allergies.';
    }
}
