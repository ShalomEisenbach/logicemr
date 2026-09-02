import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getReports from '@salesforce/apex/DiagnosticReportPanelController.getReports';
import addReport from '@salesforce/apex/DiagnosticReportPanelController.addReport';
import deleteReports from '@salesforce/apex/DiagnosticReportPanelController.deleteReports';
import markReviewed from '@salesforce/apex/DiagnosticReportService.markReviewed';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import REPORT_OBJECT from '@salesforce/schema/DiagnosticReport__c';
import DISPLAY_FIELD from '@salesforce/schema/DiagnosticReport__c.Report_Display__c';
import CODE_FIELD from '@salesforce/schema/DiagnosticReport__c.Report_Code__c';
import CODE_SYSTEM_FIELD from '@salesforce/schema/DiagnosticReport__c.Report_Code_System__c';
import CATEGORY_FIELD from '@salesforce/schema/DiagnosticReport__c.Category__c';
import STATUS_FIELD from '@salesforce/schema/DiagnosticReport__c.Status__c';
import ISSUED_FIELD from '@salesforce/schema/DiagnosticReport__c.Issued__c';
import { urlColumn, withRecordUrls } from 'c/emrNavigationUtils';

const REVIEW = 'review';
const DELETE = 'delete';

export default class EmrDiagnosticReportPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    unreviewedReports = [];
    reviewedReports = [];
    errorMessage;
    isSaving = false;
    showAddForm = false;
    codeSystem = 'LOINC';
    code = '';
    display = '';
    codeReferenceId;
    codeSearchValue;
    codeSystems = ['LOINC'];
    category = 'Laboratory';
    status = 'Final';
    effectiveDateTime;
    issuedDateTime;
    conclusion = '';
    wiredReportsResult;

    categoryOptions = [
        { label: 'Laboratory', value: 'Laboratory' },
        { label: 'Radiology', value: 'Radiology' },
        { label: 'Pathology', value: 'Pathology' }
    ];

    statusOptions = [
        { label: 'Registered', value: 'Registered' },
        { label: 'Partial', value: 'Partial' },
        { label: 'Preliminary', value: 'Preliminary' },
        { label: 'Final', value: 'Final' },
        { label: 'Amended', value: 'Amended' }
    ];

    get unreviewedColumns() {
        return this.buildColumns(true);
    }

    get reviewedColumns() {
        return this.buildColumns(false);
    }

    buildColumns(canReview) {
        const actions = [];
        if (canReview) {
            actions.push({ label: 'Mark reviewed', name: REVIEW });
        }
        actions.push({ label: 'Delete', name: DELETE });
        return [
            urlColumn('Report', 'recordUrl', 'recordLabel'),
            { label: 'Code', fieldName: CODE_FIELD.fieldApiName },
            { label: 'Category', fieldName: CATEGORY_FIELD.fieldApiName },
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            {
                label: 'Issued',
                fieldName: ISSUED_FIELD.fieldApiName,
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: 'numeric',
                    minute: '2-digit'
                }
            },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: actions
                }
            }
        ];
    }

    @wire(getReports, { patientId: '$recordId' })
    wiredReports(result) {
        this.wiredReportsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyReports(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.unreviewedReports = [];
            this.reviewedReports = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyReports(data) {
        this.unreviewedReports = await withRecordUrls(
            this,
            data.unreviewedReports || [],
            REPORT_OBJECT.objectApiName,
            { labelField: DISPLAY_FIELD.fieldApiName }
        );
        this.reviewedReports = await withRecordUrls(
            this,
            data.reviewedReports || [],
            REPORT_OBJECT.objectApiName,
            { labelField: DISPLAY_FIELD.fieldApiName }
        );
    }

    get hasUnreviewed() {
        return this.unreviewedReports.length > 0;
    }

    get hasReviewed() {
        return this.reviewedReports.length > 0;
    }

    get hasRecords() {
        return this.hasUnreviewed || this.hasReviewed;
    }

    get showEmpty() {
        return (
            !this.errorMessage &&
            this.wiredReportsResult?.data &&
            !this.hasUnreviewed &&
            !this.hasReviewed
        );
    }

    get unreviewedCards() {
        return this.toReportCards(this.unreviewedReports, true);
    }

    get reviewedCards() {
        return this.toReportCards(this.reviewedReports, false);
    }

    toReportCards(rows, canReview) {
        return (rows || []).map((row) => {
            const parts = [
                row[CODE_FIELD.fieldApiName],
                row[CODE_SYSTEM_FIELD.fieldApiName],
                row[CATEGORY_FIELD.fieldApiName],
                row[STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row[DISPLAY_FIELD.fieldApiName] || 'Diagnostic report',
                meta: parts.join(' · '),
                issuedDateTime: row[ISSUED_FIELD.fieldApiName],
                canReview,
                objectApiName: REPORT_OBJECT.objectApiName
            };
        });
    }

    get reportsRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__DiagnosticReports__r` : 'DiagnosticReports__r';
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.reportsRelationshipApiName,
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
        this.category = 'Laboratory';
        this.status = 'Final';
        this.effectiveDateTime = undefined;
        this.issuedDateTime = undefined;
        this.conclusion = '';
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

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleEffectiveChange(event) {
        this.effectiveDateTime = event.detail.value || null;
    }

    handleIssuedChange(event) {
        this.issuedDateTime = event.detail.value || null;
    }

    handleConclusionChange(event) {
        this.conclusion = event.detail.value;
    }

    async handleAdd() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addReport({
                patientId: this.recordId,
                codeSystem: this.codeSystem,
                code: this.code,
                display: this.display,
                codeReferenceId: this.codeReferenceId,
                category: this.category,
                status: this.status,
                effectiveDateTime: this.effectiveDateTime || null,
                issuedDateTime: this.issuedDateTime || null,
                conclusion: this.conclusion
            });
            this.resetAddForm();
            this.showAddForm = false;
            await refreshApex(this.wiredReportsResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleReviewCard(event) {
        this.dispatchRowAction(REVIEW, event.currentTarget.dataset.id);
    }

    handleDeleteCard(event) {
        this.dispatchRowAction(DELETE, event.currentTarget.dataset.id);
    }

    dispatchRowAction(name, recordId) {
        this.handleRowAction({
            detail: {
                action: { name },
                row: { Id: recordId }
            }
        });
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        if ((actionName !== REVIEW && actionName !== DELETE) || this.isSaving) {
            return;
        }
        if (actionName === DELETE) {
            const confirmed = await LightningConfirm.open({
                message: 'Delete this diagnostic report?',
                label: 'Delete report',
                theme: 'error'
            });
            if (!confirmed) {
                return;
            }
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const reportIds = [event.detail.row.Id];
            if (actionName === REVIEW) {
                await markReviewed({ reportIds });
            } else {
                await deleteReports({ reportIds });
            }
            await refreshApex(this.wiredReportsResult);
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
        return error?.message || 'Unable to update diagnostic reports.';
    }
}
