import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOverview from '@salesforce/apex/AdminConsoleController.getOverview';
import getNoteTemplates from '@salesforce/apex/AdminConsoleController.getNoteTemplates';
import getPractitioners from '@salesforce/apex/AdminConsoleController.getPractitioners';
import savePractitionerUsers from '@salesforce/apex/AdminConsoleController.savePractitionerUsers';
import saveEligibilitySetting from '@salesforce/apex/AdminConsoleController.saveEligibilitySetting';
import saveCommConfig from '@salesforce/apex/AdminConsoleController.saveCommConfig';
import saveMessageTemplate from '@salesforce/apex/AdminConsoleController.saveMessageTemplate';
import saveNameFormat from '@salesforce/apex/AdminConsoleController.saveNameFormat';
import scheduleReminderJob from '@salesforce/apex/AdminConsoleController.scheduleReminderJob';
import abortReminderJob from '@salesforce/apex/AdminConsoleController.abortReminderJob';
import scheduleEligibilityJob from '@salesforce/apex/AdminConsoleController.scheduleEligibilityJob';
import abortEligibilityJob from '@salesforce/apex/AdminConsoleController.abortEligibilityJob';
import runEligibilityNow from '@salesforce/apex/AdminConsoleController.runEligibilityNow';
import enqueueNameBackfill from '@salesforce/apex/AdminConsoleController.enqueueNameBackfill';
import enqueueCatalogLinkBackfill from '@salesforce/apex/AdminConsoleController.enqueueCatalogLinkBackfill';
import getNameBackfillObjects from '@salesforce/apex/AdminConsoleController.getNameBackfillObjects';
import getCatalogLinkOptions from '@salesforce/apex/AdminConsoleController.getCatalogLinkOptions';
import NOTE_TEMPLATE_OBJECT from '@salesforce/schema/NoteTemplate__c';
import CODE_REFERENCE_OBJECT from '@salesforce/schema/Code_Reference__c';

const SECTIONS = [
    { id: 'overview', label: 'Overview' },
    { id: 'credentials', label: 'Credentials' },
    { id: 'eligibility', label: 'Eligibility' },
    { id: 'communications', label: 'Communications' },
    { id: 'noteTemplates', label: 'Note templates' },
    { id: 'codeSets', label: 'Code sets' },
    { id: 'nameFormats', label: 'Name formats' },
    { id: 'practitioners', label: 'Practitioners' },
    { id: 'schedules', label: 'Schedules' },
    { id: 'mapping', label: 'Mapping' },
    { id: 'jobs', label: 'Jobs' },
    { id: 'dataQuality', label: 'Data quality' }
];

export default class EmrAdminConsole extends NavigationMixin(LightningElement) {
    @track activeSection = 'overview';
    @track overview;
    @track noteTemplates = [];
    @track practitioners = [];
    @track eligibilityDraft;
    @track commDraft;
    @track messageTemplates = [];
    @track nameFormats = [];
    @track nameBackfillObjects = [];
    @track catalogLinkOptions = [];
    @track selectedNameBackfillObject;
    @track selectedCatalogKey;
    @track eligibilityLookaheadDays = 7;
    @track showNoteModal = false;
    @track noteEditId;
    @track selectedNameFormat;
    @track selectedMessageTemplate;
    @track isSaving = false;
    @track loadError;

    wiredOverviewResult;
    wiredNotesResult;
    wiredPractitionersResult;
    wiredNameBackfillResult;
    wiredCatalogResult;
    dirtyPractitionerUsers = new Map();

    get sections() {
        return SECTIONS.map((section) => ({
            ...section,
            buttonClass:
                section.id === this.activeSection
                    ? 'slds-nav-vertical__action slds-is-active'
                    : 'slds-nav-vertical__action',
            ariaCurrent: section.id === this.activeSection ? 'page' : null
        }));
    }

    get isOverview() {
        return this.activeSection === 'overview';
    }
    get isCredentials() {
        return this.activeSection === 'credentials';
    }
    get isEligibility() {
        return this.activeSection === 'eligibility';
    }
    get isCommunications() {
        return this.activeSection === 'communications';
    }
    get isNoteTemplates() {
        return this.activeSection === 'noteTemplates';
    }
    get isCodeSets() {
        return this.activeSection === 'codeSets';
    }
    get isNameFormats() {
        return this.activeSection === 'nameFormats';
    }
    get isPractitioners() {
        return this.activeSection === 'practitioners';
    }
    get isSchedules() {
        return this.activeSection === 'schedules';
    }
    get isMapping() {
        return this.activeSection === 'mapping';
    }
    get isJobs() {
        return this.activeSection === 'jobs';
    }
    get isDataQuality() {
        return this.activeSection === 'dataQuality';
    }

    get noteTemplateObjectApiName() {
        return NOTE_TEMPLATE_OBJECT.objectApiName;
    }

    get noteModalTitle() {
        return this.noteEditId ? 'Edit note template' : 'New note template';
    }

    get stediStatusLabel() {
        return this.overview?.stediNamedCredentialPresent ? 'Present' : 'Missing';
    }

    get twilioStatusLabel() {
        return this.overview?.twilioNamedCredentialPresent ? 'Present' : 'Missing';
    }

    get reminderJobLabel() {
        return this.overview?.reminderJob?.scheduled ? 'Scheduled' : 'Not scheduled';
    }

    get eligibilityJobLabel() {
        return this.overview?.eligibilityJob?.scheduled ? 'Scheduled' : 'Not scheduled';
    }

    get reminderNextFire() {
        return this.overview?.reminderJob?.nextFireTime;
    }

    get eligibilityNextFire() {
        return this.overview?.eligibilityJob?.nextFireTime;
    }

    get nameBackfillOptions() {
        return (this.nameBackfillObjects || []).map((value) => ({ label: value, value }));
    }

    get catalogOptions() {
        return (this.catalogLinkOptions || []).map((row) => ({
            label: row.label,
            value: `${row.objectApiName}|${row.codeSystemField}|${row.codeField}|${row.lookupField}`
        }));
    }

    get practitionerColumns() {
        return [
            { label: 'Name', fieldName: 'name', type: 'text' },
            { label: 'First', fieldName: 'firstName', type: 'text' },
            { label: 'Last', fieldName: 'lastName', type: 'text' },
            { label: 'NPI', fieldName: 'npi', type: 'text' },
            {
                label: 'User Id',
                fieldName: 'userId',
                type: 'text',
                editable: true
            },
            { label: 'User Name', fieldName: 'userName', type: 'text' }
        ];
    }

    get noteColumns() {
        return [
            { label: 'Name', fieldName: 'Name', type: 'text' },
            { label: 'Shortcut', fieldName: 'Shortcut__c', type: 'text' },
            { label: 'Category', fieldName: 'Category__c', type: 'text' },
            { label: 'Active', fieldName: 'Active__c', type: 'boolean' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Edit', name: 'edit' }]
                }
            }
        ];
    }

    get nameFormatColumns() {
        return [
            { label: 'Object', fieldName: 'objectApiName', type: 'text' },
            { label: 'Format', fieldName: 'formatPattern', type: 'text' },
            { label: 'Active', fieldName: 'active', type: 'boolean' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Edit', name: 'edit' }]
                }
            }
        ];
    }

    get messageTemplateColumns() {
        return [
            { label: 'Type', fieldName: 'typeValue', type: 'text' },
            { label: 'Channel', fieldName: 'channel', type: 'text' },
            { label: 'Subject', fieldName: 'subject', type: 'text' },
            { label: 'Active', fieldName: 'active', type: 'boolean' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'Edit', name: 'edit' }]
                }
            }
        ];
    }

    @wire(getOverview)
    wiredOverview(result) {
        this.wiredOverviewResult = result;
        const { data, error } = result;
        if (data) {
            this.overview = data;
            this.eligibilityDraft = data.eligibilitySetting
                ? { ...data.eligibilitySetting }
                : null;
            this.commDraft = data.commConfig ? { ...data.commConfig } : null;
            this.messageTemplates = (data.messageTemplates || []).map((row) => ({ ...row }));
            this.nameFormats = (data.nameFormats || []).map((row) => ({ ...row }));
            this.loadError = undefined;
        } else if (error) {
            this.loadError = this.reduceError(error);
        }
    }

    @wire(getNoteTemplates)
    wiredNotes(result) {
        this.wiredNotesResult = result;
        if (result.data) {
            this.noteTemplates = result.data;
        }
    }

    @wire(getPractitioners)
    wiredPractitioners(result) {
        this.wiredPractitionersResult = result;
        if (result.data) {
            this.practitioners = result.data.map((row) => ({ ...row }));
            this.dirtyPractitionerUsers = new Map();
        }
    }

    @wire(getNameBackfillObjects)
    wiredNameBackfill(result) {
        this.wiredNameBackfillResult = result;
        if (result.data) {
            this.nameBackfillObjects = result.data;
            if (!this.selectedNameBackfillObject && result.data.length) {
                this.selectedNameBackfillObject = result.data[0];
            }
        }
    }

    @wire(getCatalogLinkOptions)
    wiredCatalog(result) {
        this.wiredCatalogResult = result;
        if (result.data) {
            this.catalogLinkOptions = result.data;
            if (!this.selectedCatalogKey && result.data.length) {
                const first = result.data[0];
                this.selectedCatalogKey = `${first.objectApiName}|${first.codeSystemField}|${first.codeField}|${first.lookupField}`;
            }
        }
    }

    handleSectionClick(event) {
        this.activeSection = event.currentTarget.dataset.section;
    }

    handleRefreshOverview() {
        this.refreshAll();
    }

    async refreshAll() {
        const jobs = [];
        if (this.wiredOverviewResult) {
            jobs.push(refreshApex(this.wiredOverviewResult));
        }
        if (this.wiredNotesResult) {
            jobs.push(refreshApex(this.wiredNotesResult));
        }
        if (this.wiredPractitionersResult) {
            jobs.push(refreshApex(this.wiredPractitionersResult));
        }
        await Promise.all(jobs);
    }

    handleEligibilityChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.eligibilityDraft = { ...this.eligibilityDraft, [field]: value };
    }

    handleCommChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        if (field === 'reminderHoursBefore' && value !== '' && value != null) {
            value = Number(value);
        }
        this.commDraft = { ...this.commDraft, [field]: value };
    }

    async handleSaveEligibility() {
        await this.runAction(() => saveEligibilitySetting({ setting: this.eligibilityDraft }), 'Eligibility setting deploy queued.');
    }

    async handleSaveComm() {
        await this.runAction(() => saveCommConfig({ config: this.commDraft }), 'Communications config deploy queued.');
    }

    handleMessageRowAction(event) {
        if (event.detail.action.name === 'edit') {
            this.selectedMessageTemplate = { ...event.detail.row };
        }
    }

    handleMessageTemplateChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.selectedMessageTemplate = { ...this.selectedMessageTemplate, [field]: value };
    }

    async handleSaveMessageTemplate() {
        await this.runAction(
            () => saveMessageTemplate({ template: this.selectedMessageTemplate }),
            'Message template deploy queued.'
        );
        this.selectedMessageTemplate = undefined;
    }

    handleCancelMessageTemplate() {
        this.selectedMessageTemplate = undefined;
    }

    handleNameFormatRowAction(event) {
        if (event.detail.action.name === 'edit') {
            this.selectedNameFormat = { ...event.detail.row };
        }
    }

    handleNameFormatChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.selectedNameFormat = { ...this.selectedNameFormat, [field]: value };
    }

    async handleSaveNameFormat() {
        await this.runAction(
            () => saveNameFormat({ nameFormat: this.selectedNameFormat }),
            'Name format deploy queued.'
        );
        this.selectedNameFormat = undefined;
    }

    handleCancelNameFormat() {
        this.selectedNameFormat = undefined;
    }

    handleNewNoteTemplate() {
        this.noteEditId = undefined;
        this.showNoteModal = true;
    }

    handleNoteRowAction(event) {
        if (event.detail.action.name === 'edit') {
            this.noteEditId = event.detail.row.Id;
            this.showNoteModal = true;
        }
    }

    handleCloseNoteModal() {
        this.showNoteModal = false;
        this.noteEditId = undefined;
    }

    async handleNoteSuccess() {
        this.showNoteModal = false;
        this.noteEditId = undefined;
        this.toast('Success', 'Note template saved.', 'success');
        if (this.wiredNotesResult) {
            await refreshApex(this.wiredNotesResult);
        }
        if (this.wiredOverviewResult) {
            await refreshApex(this.wiredOverviewResult);
        }
    }

    handleNoteError() {
        this.toast('Error', 'Could not save the note template.', 'error');
    }

    handleOpenCodeReference() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: CODE_REFERENCE_OBJECT.objectApiName,
                actionName: 'home'
            }
        });
    }

    handlePractitionerCellChange(event) {
        const draftValues = event.detail.draftValues || [];
        draftValues.forEach((draft) => {
            this.dirtyPractitionerUsers.set(draft.id, draft.userId || null);
        });
        this.practitioners = this.practitioners.map((row) => {
            const draft = draftValues.find((item) => item.id === row.id);
            return draft ? { ...row, userId: draft.userId || null } : row;
        });
    }

    async handleSavePractitioners() {
        const updates = [];
        this.dirtyPractitionerUsers.forEach((userId, practitionerId) => {
            updates.push({
                practitionerId,
                userId: userId || null
            });
        });
        if (!updates.length) {
            this.toast('Info', 'No practitioner user changes to save.', 'info');
            return;
        }
        await this.runAction(async () => {
            const count = await savePractitionerUsers({ updates });
            return { message: `${count} practitioner user link(s) updated.` };
        });
        this.dirtyPractitionerUsers = new Map();
        if (this.wiredPractitionersResult) {
            await refreshApex(this.wiredPractitionersResult);
        }
        if (this.wiredOverviewResult) {
            await refreshApex(this.wiredOverviewResult);
        }
    }

    async handleScheduleReminder() {
        await this.runAction(() => scheduleReminderJob({ cronExpression: null }), 'Reminder job scheduled.');
        await refreshApex(this.wiredOverviewResult);
    }

    async handleAbortReminder() {
        await this.runAction(() => abortReminderJob(), 'Reminder job aborted.');
        await refreshApex(this.wiredOverviewResult);
    }

    async handleScheduleEligibility() {
        await this.runAction(
            () => scheduleEligibilityJob({ cronExpression: null }),
            'Eligibility job scheduled.'
        );
        await refreshApex(this.wiredOverviewResult);
    }

    async handleAbortEligibility() {
        await this.runAction(() => abortEligibilityJob(), 'Eligibility job aborted.');
        await refreshApex(this.wiredOverviewResult);
    }

    handleLookaheadChange(event) {
        this.eligibilityLookaheadDays = Number(event.target.value);
    }

    async handleRunEligibilityNow() {
        await this.runAction(
            () => runEligibilityNow({ lookaheadDays: this.eligibilityLookaheadDays }),
            'Eligibility batch queued.'
        );
    }

    handleNameBackfillChange(event) {
        this.selectedNameBackfillObject = event.detail.value;
    }

    async handleEnqueueNameBackfill() {
        await this.runAction(
            () => enqueueNameBackfill({ objectApiName: this.selectedNameBackfillObject }),
            'Name backfill queued.'
        );
    }

    handleCatalogChange(event) {
        this.selectedCatalogKey = event.detail.value;
    }

    async handleEnqueueCatalogLink() {
        const parts = (this.selectedCatalogKey || '').split('|');
        if (parts.length !== 4) {
            this.toast('Error', 'Select a catalog link target.', 'error');
            return;
        }
        await this.runAction(
            () =>
                enqueueCatalogLinkBackfill({
                    objectApiName: parts[0],
                    codeSystemField: parts[1],
                    codeField: parts[2],
                    lookupField: parts[3]
                }),
            'Catalog link backfill queued.'
        );
    }

    async runAction(actionFn, fallbackSuccessMessage) {
        this.isSaving = true;
        try {
            const result = await actionFn();
            const message =
                result && result.message ? result.message : fallbackSuccessMessage || 'Done.';
            this.toast('Success', message, 'success');
            return result;
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
            return null;
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}
