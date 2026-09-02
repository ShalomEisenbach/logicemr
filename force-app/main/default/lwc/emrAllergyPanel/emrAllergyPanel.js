import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getAllergies from '@salesforce/apex/AllergyPanelController.getAllergies';
import addAllergy from '@salesforce/apex/AllergyPanelController.addAllergy';
import inactivateAllergies from '@salesforce/apex/AllergyPanelController.inactivateAllergies';
import deleteAllergies from '@salesforce/apex/AllergyPanelController.deleteAllergies';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import ALLERGY_OBJECT from '@salesforce/schema/AllergyIntolerance__c';
import DISPLAY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Allergen_Display__c';
import TYPE_FIELD from '@salesforce/schema/AllergyIntolerance__c.Type__c';
import CATEGORY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Category__c';
import CRITICALITY_FIELD from '@salesforce/schema/AllergyIntolerance__c.Criticality__c';
import REACTION_FIELD from '@salesforce/schema/AllergyIntolerance__c.Reaction__c';
import STATUS_FIELD from '@salesforce/schema/AllergyIntolerance__c.Clinical_Status__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const INACTIVATE = 'inactivate';
const DELETE = 'delete';

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

    get columns() {
        return [
            urlColumn('Allergen', 'recordUrl', 'recordLabel'),
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
    }

    get allergyObjectApiName() {
        return ALLERGY_OBJECT.objectApiName;
    }

    @wire(getAllergies, { patientId: '$recordId' })
    wiredAllergies(result) {
        this.wiredAllergiesResult = result;
        const { data, error } = result;
        if (data) {
            this.applyAllergies(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.allergies = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyAllergies(data) {
        this.allergies = await withRecordUrls(this, data, ALLERGY_OBJECT.objectApiName, {
            labelField: DISPLAY_FIELD.fieldApiName
        });
    }

    get hasAllergies() {
        return this.allergies && this.allergies.length > 0;
    }

    get showEmpty() {
        return this.allergies && this.allergies.length === 0 && !this.errorMessage;
    }

    get allergyCards() {
        return (this.allergies || []).map((row) => {
            const status = row[STATUS_FIELD.fieldApiName];
            const parts = [
                row[TYPE_FIELD.fieldApiName],
                row[CATEGORY_FIELD.fieldApiName],
                row[CRITICALITY_FIELD.fieldApiName],
                status
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[DISPLAY_FIELD.fieldApiName] || 'Allergy',
                meta: parts.join(' · '),
                detail: row[REACTION_FIELD.fieldApiName] || '',
                canInactivate: status === 'Active',
                objectApiName: ALLERGY_OBJECT.objectApiName
            };
        });
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
        actions.push({ label: 'Delete', name: DELETE });
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
        this.reaction = '';
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
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredAllergiesResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleInactivateCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: INACTIVATE },
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
        if ((actionName !== INACTIVATE && actionName !== DELETE) || this.isSaving) {
            return;
        }
        if (actionName === DELETE) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this allergy?',
                label: 'Delete allergy',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const allergyIds = [event.detail.row.Id];
            if (actionName === INACTIVATE) {
                await inactivateAllergies({ allergyIds });
            } else {
                await deleteAllergies({ allergyIds });
            }
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
