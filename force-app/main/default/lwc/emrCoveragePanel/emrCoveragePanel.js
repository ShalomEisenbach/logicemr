import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import getCoverages from '@salesforce/apex/CoveragePanelController.getCoverages';
import saveCoverage from '@salesforce/apex/CoveragePanelController.saveCoverage';
import inactivateCoverages from '@salesforce/apex/CoveragePanelController.inactivateCoverages';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import COVERAGE_OBJECT from '@salesforce/schema/Coverage__c';
import PAYER_OBJECT from '@salesforce/schema/Payer__c';
import PAYER_FIELD from '@salesforce/schema/Coverage__c.Payer__c';
import PAYER_NAME_FIELD from '@salesforce/schema/Payer__c.Name';
import PAYER_ACTIVE_FIELD from '@salesforce/schema/Payer__c.Active__c';
import MEMBER_FIELD from '@salesforce/schema/Coverage__c.Member_Id__c';
import PLAN_FIELD from '@salesforce/schema/Coverage__c.Plan_Name__c';
import PRIORITY_FIELD from '@salesforce/schema/Coverage__c.Priority__c';
import STATUS_FIELD from '@salesforce/schema/Coverage__c.Status__c';
import START_FIELD from '@salesforce/schema/Coverage__c.Effective_Start__c';
import END_FIELD from '@salesforce/schema/Coverage__c.Effective_End__c';
import TYPE_FIELD from '@salesforce/schema/Coverage__c.Type__c';
import GROUP_FIELD from '@salesforce/schema/Coverage__c.Group_Number__c';
import RELATIONSHIP_FIELD from '@salesforce/schema/Coverage__c.Relationship_to_Subscriber__c';
import SUBSCRIBER_FIELD from '@salesforce/schema/Coverage__c.Subscriber_Name__c';
import { urlColumn, withRecordUrls, recordViewPageRef } from 'c/emrNavigationUtils';

const EDIT = 'edit';
const INACTIVATE = 'inactivate';
const STATUS_ACTIVE = 'Active';

export default class EmrCoveragePanel extends NavigationMixin(LightningElement) {
    @api recordId;

    coverages = [];
    errorMessage;
    isSaving = false;
    showForm = false;
    editingId;
    payerId;
    memberId = '';
    groupNumber = '';
    planName = '';
    coverageType = 'Medical';
    relationshipToSubscriber = 'Self';
    subscriberName = '';
    status = STATUS_ACTIVE;
    effectiveStart;
    effectiveEnd;
    priority = 'Primary';
    wiredCoveragesResult;

    typeOptions = [
        { label: 'Medical', value: 'Medical' },
        { label: 'Dental', value: 'Dental' },
        { label: 'Vision', value: 'Vision' },
        { label: 'Pharmacy', value: 'Pharmacy' }
    ];

    relationshipOptions = [
        { label: 'Self', value: 'Self' },
        { label: 'Spouse', value: 'Spouse' },
        { label: 'Child', value: 'Child' },
        { label: 'Other', value: 'Other' }
    ];

    statusOptions = [
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' },
        { label: 'Draft', value: 'Draft' }
    ];

    priorityOptions = [
        { label: 'Primary', value: 'Primary' },
        { label: 'Secondary', value: 'Secondary' },
        { label: 'Tertiary', value: 'Tertiary' }
    ];

    payerFilter = {
        criteria: [
            {
                fieldPath: PAYER_ACTIVE_FIELD.fieldApiName,
                operator: 'eq',
                value: true
            }
        ]
    };

    get payerObjectApiName() {
        return PAYER_OBJECT.objectApiName;
    }

    get formTitle() {
        return this.editingId ? 'Edit coverage' : 'Add coverage';
    }

    get columns() {
        return [
            urlColumn('Payer', 'payerUrl', 'payerName'),
            { label: 'Member ID', fieldName: MEMBER_FIELD.fieldApiName },
            { label: 'Plan', fieldName: PLAN_FIELD.fieldApiName, wrapText: true },
            { label: 'Priority', fieldName: PRIORITY_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            {
                label: 'Start',
                fieldName: START_FIELD.fieldApiName,
                type: 'date',
                typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
            },
            {
                label: 'End',
                fieldName: END_FIELD.fieldApiName,
                type: 'date',
                typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: this.getRowActions.bind(this)
                }
            }
        ];
    }

    @wire(getCoverages, { patientId: '$recordId' })
    wiredCoverages(result) {
        this.wiredCoveragesResult = result;
        const { data, error } = result;
        if (data) {
            this.applyCoverages(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.coverages = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyCoverages(data) {
        const withNames = (data || []).map((row) => {
            const payerId = row[PAYER_FIELD.fieldApiName];
            return {
                ...row,
                payerId,
                payerName: this.formatPayer(row) || 'Coverage',
                dateLabel: this.formatDateRange(row)
            };
        });
        const withCoverageUrls = await withRecordUrls(this, withNames, COVERAGE_OBJECT.objectApiName, {
            labelField: 'payerName'
        });
        this.coverages = await Promise.all(
            withCoverageUrls.map(async (row) => {
                let payerUrl = '';
                if (row.payerId) {
                    try {
                        payerUrl = await this[NavigationMixin.GenerateUrl](
                            recordViewPageRef(row.payerId, PAYER_OBJECT.objectApiName)
                        );
                    } catch (e) {
                        payerUrl = '';
                    }
                }
                return { ...row, payerUrl };
            })
        );
    }

    formatPayer(row) {
        const relationshipName = PAYER_FIELD.fieldApiName.replace(/__c$/, '__r');
        const payer = row[relationshipName];
        return payer ? payer[PAYER_NAME_FIELD.fieldApiName] || payer.Name || '' : '';
    }

    formatDateRange(row) {
        const start = this.formatDate(row[START_FIELD.fieldApiName]);
        const end = this.formatDate(row[END_FIELD.fieldApiName]);
        if (start && end) {
            return `${start} – ${end}`;
        }
        return start || end || '';
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        try {
            const date = new Date(value);
            if (Number.isNaN(date.getTime())) {
                return String(value);
            }
            return date.toLocaleDateString(undefined, {
                year: 'numeric',
                month: 'short',
                day: '2-digit'
            });
        } catch (e) {
            return String(value);
        }
    }

    get hasCoverages() {
        return this.coverages && this.coverages.length > 0;
    }

    get showEmpty() {
        return this.coverages && this.coverages.length === 0 && !this.errorMessage;
    }

    get coverageCards() {
        return (this.coverages || []).map((row) => {
            const status = row[STATUS_FIELD.fieldApiName];
            const parts = [
                row[MEMBER_FIELD.fieldApiName],
                row[PLAN_FIELD.fieldApiName],
                row[PRIORITY_FIELD.fieldApiName],
                status
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row.payerName || 'Coverage',
                meta: parts.join(' · '),
                detail: row.dateLabel || '',
                canInactivate: status && status !== 'Inactive',
                objectApiName: COVERAGE_OBJECT.objectApiName
            };
        });
    }

    get coveragesRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Coverages__r` : 'Coverages__r';
    }

    getRowActions(row, doneCallback) {
        const actions = [{ label: 'Edit', name: EDIT }];
        if (row[STATUS_FIELD.fieldApiName] !== 'Inactive') {
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
                relationshipApiName: this.coveragesRelationshipApiName,
                actionName: 'view'
            }
        });
    }

    handleToggleAdd() {
        this.resetForm();
        this.editingId = undefined;
        this.showForm = true;
        this.errorMessage = undefined;
    }

    handleCloseForm() {
        this.showForm = false;
        this.errorMessage = undefined;
        this.resetForm();
    }

    resetForm() {
        this.editingId = undefined;
        this.payerId = undefined;
        this.memberId = '';
        this.groupNumber = '';
        this.planName = '';
        this.coverageType = 'Medical';
        this.relationshipToSubscriber = 'Self';
        this.subscriberName = '';
        this.status = STATUS_ACTIVE;
        this.effectiveStart = undefined;
        this.effectiveEnd = undefined;
        this.priority = 'Primary';
    }

    populateForm(row) {
        this.editingId = row.Id;
        this.payerId = row[PAYER_FIELD.fieldApiName];
        this.memberId = row[MEMBER_FIELD.fieldApiName] || '';
        this.groupNumber = row[GROUP_FIELD.fieldApiName] || '';
        this.planName = row[PLAN_FIELD.fieldApiName] || '';
        this.coverageType = row[TYPE_FIELD.fieldApiName] || 'Medical';
        this.relationshipToSubscriber = row[RELATIONSHIP_FIELD.fieldApiName] || 'Self';
        this.subscriberName = row[SUBSCRIBER_FIELD.fieldApiName] || '';
        this.status = row[STATUS_FIELD.fieldApiName] || STATUS_ACTIVE;
        this.effectiveStart = row[START_FIELD.fieldApiName];
        this.effectiveEnd = row[END_FIELD.fieldApiName];
        this.priority = row[PRIORITY_FIELD.fieldApiName] || 'Primary';
    }

    handlePayerChange(event) {
        this.payerId = event.detail.recordId;
        this.errorMessage = undefined;
    }

    handleMemberChange(event) {
        this.memberId = event.detail.value;
    }

    handleGroupChange(event) {
        this.groupNumber = event.detail.value;
    }

    handlePlanChange(event) {
        this.planName = event.detail.value;
    }

    handleTypeChange(event) {
        this.coverageType = event.detail.value;
    }

    handleRelationshipChange(event) {
        this.relationshipToSubscriber = event.detail.value;
    }

    handleSubscriberChange(event) {
        this.subscriberName = event.detail.value;
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleStartChange(event) {
        this.effectiveStart = event.detail.value;
    }

    handleEndChange(event) {
        this.effectiveEnd = event.detail.value;
    }

    handlePriorityChange(event) {
        this.priority = event.detail.value;
    }

    async handleSave() {
        if (this.isSaving) {
            return;
        }
        if (!this.payerId) {
            this.errorMessage = 'Payer is required.';
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await saveCoverage({
                coverageId: this.editingId,
                patientId: this.recordId,
                payerId: this.payerId,
                memberId: this.memberId,
                groupNumber: this.groupNumber,
                planName: this.planName,
                coverageType: this.coverageType,
                relationshipToSubscriber: this.relationshipToSubscriber,
                subscriberName: this.subscriberName,
                status: this.status,
                effectiveStart: this.effectiveStart || null,
                effectiveEnd: this.effectiveEnd || null,
                priority: this.priority
            });
            this.showForm = false;
            this.resetForm();
            await refreshApex(this.wiredCoveragesResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleEditCard(event) {
        const row = this.coverages.find((item) => item.Id === event.currentTarget.dataset.id);
        if (!row) {
            return;
        }
        this.handleRowAction({
            detail: {
                action: { name: EDIT },
                row
            }
        });
    }

    handleInactivateCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: INACTIVATE },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if (actionName === EDIT) {
            this.populateForm(event.detail.row);
            this.showForm = true;
            this.errorMessage = undefined;
            return;
        }
        if (actionName !== INACTIVATE || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await inactivateCoverages({ coverageIds: [event.detail.row.Id] });
            await refreshApex(this.wiredCoveragesResult);
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
        return error?.message || 'Unable to update coverage.';
    }
}
