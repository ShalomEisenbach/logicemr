import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getHome from '@salesforce/apex/ProviderHomeController.getHome';
import markReviewed from '@salesforce/apex/DiagnosticReportService.markReviewed';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import REPORT_OBJECT from '@salesforce/schema/DiagnosticReport__c';
import NOTE_OBJECT from '@salesforce/schema/ClinicalNote__c';
import PATIENT_FIELD from '@salesforce/schema/Encounter__c.Patient__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import PATIENT_STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';
import CLASS_FIELD from '@salesforce/schema/Encounter__c.Class__c';
import ENCOUNTER_STATUS_FIELD from '@salesforce/schema/Encounter__c.Status__c';
import START_FIELD from '@salesforce/schema/Encounter__c.Start__c';
import REASON_FIELD from '@salesforce/schema/Encounter__c.Reason__c';
import REPORT_DISPLAY_FIELD from '@salesforce/schema/DiagnosticReport__c.Report_Display__c';
import REPORT_STATUS_FIELD from '@salesforce/schema/DiagnosticReport__c.Status__c';
import ISSUED_FIELD from '@salesforce/schema/DiagnosticReport__c.Issued__c';
import NOTE_TYPE_FIELD from '@salesforce/schema/ClinicalNote__c.Note_Type__c';

export default class EmrProviderHome extends NavigationMixin(LightningElement) {
    errorMessage;
    isLoading = true;
    isSaving = false;
    pendingSearchFocus = false;
    metrics = emptyMetrics();
    todaysEncounters = [];
    resultsToReview = [];
    unsignedNotes = [];
    recentPatients = [];
    wiredHomeResult;

    @wire(getHome)
    wiredHome(result) {
        this.wiredHomeResult = result;
        const { data, error } = result;
        if (data) {
            this.applyPayload(data);
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.applyPayload(null);
            this.errorMessage = this.reduceError(error);
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (!this.pendingSearchFocus) {
            return;
        }
        this.pendingSearchFocus = false;
        const search = this.template.querySelector('c-emr-patient-search');
        if (search) {
            search.focusSearch();
        }
    }

    applyPayload(data) {
        const metrics = data && data.metrics ? data.metrics : emptyMetrics();
        const lists = data && data.lists ? data.lists : {};
        this.metrics = {
            myActivePatients: metrics.myActivePatients || 0,
            openEncounters: metrics.openEncounters || 0,
            resultsToReview: metrics.resultsToReview || 0,
            unsignedNotes: metrics.unsignedNotes || 0
        };
        this.todaysEncounters = this.mapEncounters(lists.todaysEncounters || []);
        this.resultsToReview = this.mapReports(lists.resultsToReview || []);
        this.unsignedNotes = this.mapNotes(lists.unsignedNotes || []);
        this.recentPatients = this.mapPatients(data && data.recentPatients ? data.recentPatients : []);
    }

    get metricItems() {
        return [
            { key: 'patients', label: 'Active patients', value: this.metrics.myActivePatients },
            { key: 'encounters', label: 'Open encounters', value: this.metrics.openEncounters },
            { key: 'results', label: 'Results to review', value: this.metrics.resultsToReview },
            { key: 'notes', label: 'Unsigned notes', value: this.metrics.unsignedNotes }
        ];
    }

    get hasTodaysEncounters() {
        return this.todaysEncounters.length > 0;
    }

    get hasResultsToReview() {
        return this.resultsToReview.length > 0;
    }

    get hasUnsignedNotes() {
        return this.unsignedNotes.length > 0;
    }

    get hasRecentPatients() {
        return this.recentPatients.length > 0;
    }

    get showContent() {
        return !this.isLoading;
    }

    handleNewPatient() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: PATIENT_OBJECT.objectApiName,
                actionName: 'new'
            }
        });
    }

    handleNewEncounter() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: ENCOUNTER_OBJECT.objectApiName,
                actionName: 'new'
            }
        });
    }

    handleFindPatient() {
        this.pendingSearchFocus = true;
        const search = this.template.querySelector('c-emr-patient-search');
        if (search) {
            this.pendingSearchFocus = false;
            search.focusSearch();
        }
    }

    async handleMarkReviewed(event) {
        const reportId = event.currentTarget.dataset.id;
        if (!reportId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await markReviewed({ reportIds: [reportId] });
            if (this.wiredHomeResult) {
                await refreshApex(this.wiredHomeResult);
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    mapEncounters(rows) {
        return rows.map((row) => {
            const parts = [
                this.patientName(row),
                row[CLASS_FIELD.fieldApiName],
                row[ENCOUNTER_STATUS_FIELD.fieldApiName],
                this.formatDateTime(row[START_FIELD.fieldApiName])
            ].filter((part) => part);
            const reason = row[REASON_FIELD.fieldApiName];
            return {
                id: row.Id,
                title: this.patientName(row) || row.Name || 'Encounter',
                meta: parts.slice(1).join(' · '),
                detail: reason || '',
                objectApiName: ENCOUNTER_OBJECT.objectApiName
            };
        });
    }

    mapReports(rows) {
        return rows.map((row) => {
            const title = row[REPORT_DISPLAY_FIELD.fieldApiName] || row.Name || 'Diagnostic report';
            const parts = [
                this.patientName(row),
                row[REPORT_STATUS_FIELD.fieldApiName],
                this.formatDateTime(row[ISSUED_FIELD.fieldApiName])
            ].filter((part) => part);
            return {
                id: row.Id,
                title,
                meta: parts.join(' · '),
                objectApiName: REPORT_OBJECT.objectApiName
            };
        });
    }

    mapNotes(rows) {
        return rows.map((row) => {
            const parts = [
                this.patientName(row),
                row[NOTE_TYPE_FIELD.fieldApiName],
                this.formatDateTime(row.LastModifiedDate)
            ].filter((part) => part);
            return {
                id: row.Id,
                title: this.patientName(row) || row.Name || 'Clinical note',
                meta: parts.slice(1).join(' · '),
                objectApiName: NOTE_OBJECT.objectApiName
            };
        });
    }

    mapPatients(rows) {
        return rows.map((row) => {
            const name = [row[LAST_NAME_FIELD.fieldApiName], row[FIRST_NAME_FIELD.fieldApiName]]
                .filter((part) => part)
                .join(', ');
            const parts = [
                row[MRN_FIELD.fieldApiName],
                this.formatDate(row[DOB_FIELD.fieldApiName]),
                row[PATIENT_STATUS_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: name || row.Name || 'Patient',
                meta: parts.join(' · '),
                objectApiName: PATIENT_OBJECT.objectApiName
            };
        });
    }

    patientName(row) {
        const relationshipName = PATIENT_FIELD.fieldApiName.replace(/__c$/, '__r');
        const patient = row[relationshipName];
        if (!patient) {
            return '';
        }
        const composed = [patient[LAST_NAME_FIELD.fieldApiName], patient[FIRST_NAME_FIELD.fieldApiName]]
            .filter((part) => part)
            .join(', ');
        return composed || patient.Name || '';
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }
        const parsed = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(parsed.getTime())) {
            return String(value);
        }
        return parsed.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        const parsed = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(parsed.getTime())) {
            return String(value);
        }
        return parsed.toLocaleDateString();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load provider home.';
    }
}

function emptyMetrics() {
    return {
        myActivePatients: 0,
        openEncounters: 0,
        resultsToReview: 0,
        unsignedNotes: 0
    };
}
