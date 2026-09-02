import { LightningElement } from 'lwc';
import findDuplicates from '@salesforce/apex/DuplicatePatientController.findDuplicates';
import hasViewDataQuality from '@salesforce/customPermission/LogicEMR_View_Data_Quality';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import NAME_FIELD from '@salesforce/schema/Patient__c.Name';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import DOB_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';

function formatDob(value) {
    if (!value) {
        return '';
    }
    const parsed = value instanceof Date ? value : new Date(`${value}T00:00:00`);
    if (Number.isNaN(parsed.getTime())) {
        return String(value);
    }
    return parsed.toLocaleDateString();
}

function formatDateTime(value) {
    if (!value) {
        return '';
    }
    const parsed = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(parsed.getTime())) {
        return String(value);
    }
    return parsed.toLocaleString();
}

export default class EmrDuplicatePatients extends LightningElement {
    groups = [];
    groupLimit;
    truncated = false;
    errorMessage;
    isLoading = true;

    get canView() {
        return hasViewDataQuality;
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.hasGroups && !this.errorMessage;
    }

    get showTruncated() {
        return this.truncated && this.groupLimit != null;
    }

    get truncatedMessage() {
        return `Showing first ${this.groupLimit} groups`;
    }

    connectedCallback() {
        if (!this.canView) {
            this.isLoading = false;
            return;
        }
        this.loadDuplicates();
    }

    async loadDuplicates() {
        this.isLoading = true;
        try {
            const result = await findDuplicates();
            this.groups = this.mapGroups(result?.groups || []);
            this.groupLimit = result?.groupLimit;
            this.truncated = !!result?.truncated;
            this.errorMessage = undefined;
        } catch (error) {
            this.groups = [];
            this.truncated = false;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    mapGroups(groups) {
        return groups.map((group, index) => {
            const name = [group.lastName, group.firstName].filter((part) => part).join(', ') || 'Name not set';
            const dob = formatDob(group.dateOfBirth) || 'DOB not set';
            const memberCount = group.memberCount || (group.members || []).length;
            return {
                key: `${name}|${dob}|${index}`,
                heading: `${name} · ${dob}`,
                countLabel: `${memberCount} records`,
                members: (group.members || []).map((row) => {
                    const label = row[NAME_FIELD.fieldApiName] || name;
                    return {
                        id: row.Id,
                        label,
                        mrn: row[MRN_FIELD.fieldApiName] || '',
                        dob: formatDob(row[DOB_FIELD.fieldApiName]),
                        status: row[STATUS_FIELD.fieldApiName] || '',
                        created: formatDateTime(row.CreatedDate),
                        objectApiName: PATIENT_OBJECT.objectApiName
                    };
                })
            };
        });
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load suspected duplicates.';
    }
}
