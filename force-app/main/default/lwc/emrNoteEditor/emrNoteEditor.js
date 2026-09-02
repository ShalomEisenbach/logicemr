import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getActiveTemplates from '@salesforce/apex/NoteEditorController.getActiveTemplates';
import getCurrentNote from '@salesforce/apex/NoteEditorController.getCurrentNote';
import saveDraft from '@salesforce/apex/NoteEditorController.saveDraft';
import signNote from '@salesforce/apex/NoteEditorController.signNote';

const CATEGORY_ORDER = ['Progress Note', 'ROS', 'Physical Exam', 'Assessment/Plan', 'Other'];

export default class EmrNoteEditor extends LightningElement {
    noteId;
    noteType = 'Progress Note';
    body = '';
    status = 'Draft';
    signedDate;
    errorMessage;
    isSaving = false;
    isLoading = false;
    templatesOpen = true;
    templates = [];
    skipShortcutExpand = false;

    noteTypeOptions = [
        { label: 'Progress Note', value: 'Progress Note' },
        { label: 'H&P', value: 'H&P' },
        { label: 'Discharge Summary', value: 'Discharge Summary' },
        { label: 'Consult', value: 'Consult' },
        { label: 'Other', value: 'Other' }
    ];

    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadNote();
        }
    }

    @wire(getActiveTemplates)
    wiredTemplates({ data, error }) {
        if (data) {
            this.templates = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.templates = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get isLocked() {
        return this.status === 'Signed';
    }

    get isBusy() {
        return this.isSaving || this.isLoading;
    }

    get actionsDisabled() {
        return this.isBusy || this.isLocked;
    }

    get panelToggleLabel() {
        return this.templatesOpen ? 'Hide templates' : 'Show templates';
    }

    get editorClass() {
        return this.templatesOpen
            ? 'slds-col slds-size_1-of-1 slds-medium-size_2-of-3'
            : 'slds-col slds-size_1-of-1';
    }

    get templateGroups() {
        const byCategory = new Map();
        for (const row of this.templates) {
            const category = row.Category__c || 'Other';
            if (!byCategory.has(category)) {
                byCategory.set(category, []);
            }
            byCategory.get(category).push({
                id: row.Id,
                name: row.Name,
                body: row.Body__c || '',
                shortcut: row.Shortcut__c || '',
                shortcutLabel: row.Shortcut__c ? row.Shortcut__c : ''
            });
        }
        const known = CATEGORY_ORDER.filter((category) => byCategory.has(category)).map((category) => ({
            key: category,
            category,
            templates: byCategory.get(category)
        }));
        const extras = [...byCategory.keys()]
            .filter((category) => !CATEGORY_ORDER.includes(category))
            .sort()
            .map((category) => ({
                key: category,
                category,
                templates: byCategory.get(category)
            }));
        return [...known, ...extras];
    }

    get hasTemplates() {
        return this.templates && this.templates.length > 0;
    }

    get shortcuts() {
        return this.templates
            .filter((row) => row.Shortcut__c)
            .sort((a, b) => b.Shortcut__c.length - a.Shortcut__c.length);
    }

    handleNoteTypeChange(event) {
        this.noteType = event.detail.value;
    }

    handleBodyChange(event) {
        const value = event.detail.value || '';
        if (this.isLocked || this.skipShortcutExpand) {
            this.body = value;
            return;
        }
        const expanded = this.expandShortcuts(value);
        if (expanded !== value) {
            this.skipShortcutExpand = true;
            this.body = expanded;
            Promise.resolve().then(() => {
                this.skipShortcutExpand = false;
            });
        } else {
            this.body = value;
        }
    }

    handleToggleTemplates() {
        this.templatesOpen = !this.templatesOpen;
    }

    handleInsertTemplate(event) {
        if (this.isLocked) {
            return;
        }
        const templateId = event.currentTarget.dataset.id;
        const template = this.templates.find((row) => row.Id === templateId);
        if (!template) {
            return;
        }
        this.insertHtml(template.Body__c || '');
    }

    handleNewNote() {
        this.noteId = undefined;
        this.noteType = 'Progress Note';
        this.body = '';
        this.status = 'Draft';
        this.signedDate = undefined;
        this.errorMessage = undefined;
    }

    async handleSaveDraft() {
        await this.persist(false);
    }

    async handleSign() {
        await this.persist(true);
    }

    async persist(shouldSign) {
        if (this.isBusy || this.isLocked) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const action = shouldSign ? signNote : saveDraft;
            const state = await action({
                encounterId: this.recordId,
                noteId: this.noteId,
                noteType: this.noteType,
                body: this.body
            });
            this.applyState(state);
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(
                new ShowToastEvent({
                    title: shouldSign ? 'Note signed' : 'Draft saved',
                    message: shouldSign
                        ? 'The note is signed and locked.'
                        : 'The note was saved as a draft.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async loadNote() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const state = await getCurrentNote({ encounterId: this._recordId });
            this.applyState(state);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyState(state) {
        this.noteId = state?.noteId;
        this.noteType = state?.noteType || 'Progress Note';
        this.body = state?.body || '';
        this.status = state?.status || 'Draft';
        this.signedDate = state?.signedDate;
    }

    insertHtml(snippet) {
        if (!snippet) {
            return;
        }
        const editor = this.template.querySelector('[data-id="note-body"]');
        if (editor) {
            editor.focus();
            try {
                const inserted = document.execCommand('insertHTML', false, snippet);
                if (inserted && editor.value != null) {
                    this.body = editor.value;
                    return;
                }
            } catch (e) {
                // Fall through to append when the rich-text selection is unavailable.
            }
        }
        this.body = this.mergeRichText(this.body, snippet);
    }

    mergeRichText(current, snippet) {
        if (!current) {
            return snippet;
        }
        return `${current}${snippet}`;
    }

    expandShortcuts(html) {
        let result = html;
        for (const row of this.shortcuts) {
            const shortcut = row.Shortcut__c;
            const escaped = shortcut.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const matcher = new RegExp(escaped + '(?![\\w])');
            if (matcher.test(result)) {
                result = result.replace(matcher, row.Body__c || '');
                break;
            }
        }
        return result;
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to save note.';
    }
}
