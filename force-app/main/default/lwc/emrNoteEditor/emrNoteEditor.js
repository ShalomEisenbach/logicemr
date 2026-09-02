import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getActiveTemplates from '@salesforce/apex/NoteEditorController.getActiveTemplates';
import getNotes from '@salesforce/apex/NoteEditorController.getNotes';
import saveDraft from '@salesforce/apex/NoteEditorController.saveDraft';
import signNote from '@salesforce/apex/NoteEditorController.signNote';
import CLINICAL_NOTE_OBJECT from '@salesforce/schema/ClinicalNote__c';

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
    showEditor = false;
    notes = [];
    templates = [];
    templateSearch = '';
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
            this.loadNotes();
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

    get clinicalNoteObjectApiName() {
        return CLINICAL_NOTE_OBJECT.objectApiName;
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

    get hasNotes() {
        return this.notes && this.notes.length > 0;
    }

    get filteredTemplates() {
        const query = (this.templateSearch || '').trim().toLowerCase();
        if (!query) {
            return this.templates || [];
        }
        return (this.templates || []).filter((row) => {
            const name = (this.templateValue(row, 'Name') || '').toLowerCase();
            const shortcut = (this.templateValue(row, 'Shortcut__c') || '').toLowerCase();
            const category = (this.templateValue(row, 'Category__c') || '').toLowerCase();
            return name.includes(query) || shortcut.includes(query) || category.includes(query);
        });
    }

    get templateGroups() {
        const byCategory = new Map();
        for (const row of this.filteredTemplates) {
            const category = this.templateValue(row, 'Category__c') || 'Other';
            if (!byCategory.has(category)) {
                byCategory.set(category, []);
            }
            const shortcut = this.templateValue(row, 'Shortcut__c') || '';
            byCategory.get(category).push({
                id: this.templateValue(row, 'Id') || row.Id,
                name: this.templateValue(row, 'Name') || row.Name,
                body: this.templateValue(row, 'Body__c') || '',
                shortcut,
                shortcutLabel: shortcut
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

    get hasMatchingTemplates() {
        return this.filteredTemplates.length > 0;
    }

    get emptyTemplatesMessage() {
        if (!this.hasTemplates) {
            return 'No active templates.';
        }
        return 'No matching templates.';
    }

    get shortcuts() {
        return this.templates
            .filter((row) => this.templateValue(row, 'Shortcut__c'))
            .sort(
                (a, b) =>
                    this.templateValue(b, 'Shortcut__c').length - this.templateValue(a, 'Shortcut__c').length
            );
    }

    handleOpenEditor() {
        this.handleNewNote();
        this.showEditor = true;
        this.errorMessage = undefined;
    }

    handleCloseEditor() {
        this.showEditor = false;
        this.templateSearch = '';
        this.errorMessage = undefined;
        this.loadNotes();
    }

    handleInlineNoteTypeChange(event) {
        const noteId = event.currentTarget.dataset.noteId;
        this.updateNoteCard(noteId, { noteType: event.detail.value });
    }

    handleInlineBodyChange(event) {
        const noteId = event.currentTarget.dataset.noteId;
        const raw = event.detail && event.detail.value != null ? event.detail.value : event.target.value;
        const value = raw || '';
        if (this.skipShortcutExpand) {
            return;
        }
        const expanded = this.expandShortcuts(value);
        if (expanded !== value) {
            this.skipShortcutExpand = true;
            const editor = this.inlineEditor(noteId);
            if (editor) {
                editor.value = expanded;
            }
            Promise.resolve().then(() => {
                this.skipShortcutExpand = false;
            });
        }
    }

    handleInlineSaveDraft(event) {
        const noteId = event.currentTarget.dataset.noteId;
        this.persistCard(noteId, false);
    }

    handleInlineSign(event) {
        const noteId = event.currentTarget.dataset.noteId;
        this.persistCard(noteId, true);
    }

    handleNoteTypeChange(event) {
        this.noteType = event.detail.value;
    }

    handleBodyChange(event) {
        const raw = event.detail && event.detail.value != null ? event.detail.value : event.target.value;
        const value = raw || '';
        if (this.isLocked || this.skipShortcutExpand) {
            this.body = value;
            return;
        }
        const expanded = this.expandShortcuts(value);
        if (expanded !== value) {
            this.skipShortcutExpand = true;
            this.syncBody(expanded);
            Promise.resolve().then(() => {
                this.skipShortcutExpand = false;
            });
        } else {
            this.body = value;
        }
    }

    handleTemplateSearch(event) {
        const value = event.detail && event.detail.value != null ? event.detail.value : event.target.value;
        this.templateSearch = value || '';
    }

    handleInsertTemplate(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.isLocked) {
            return;
        }
        const templateId = event.currentTarget.dataset.templateId;
        const template = (this.templates || []).find((row) =>
            this.sameRecordId(this.templateValue(row, 'Id') || row.Id, templateId)
        );
        const snippet = this.toPlainText(this.templateValue(template, 'Body__c'));
        if (!snippet) {
            return;
        }
        this.body = this.currentBody();
        this.insertText(snippet);
    }

    sameRecordId(left, right) {
        if (!left || !right) {
            return false;
        }
        if (left === right) {
            return true;
        }
        return String(left).substring(0, 15) === String(right).substring(0, 15);
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
                body: this.currentBody()
            });
            this.applyState(state);
            await this.loadNotes();
            this.dispatchEvent(new RefreshEvent());
            this.toastPersist(shouldSign);
            if (shouldSign) {
                this.showEditor = false;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async persistCard(noteId, shouldSign) {
        if (this.isBusy || !noteId) {
            return;
        }
        const card = this.notes.find((note) => this.sameRecordId(note.id, noteId));
        if (!card || card.isLocked) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const action = shouldSign ? signNote : saveDraft;
            await action({
                encounterId: this.recordId,
                noteId,
                noteType: this.inlineNoteType(noteId),
                body: this.inlineBody(noteId)
            });
            await this.loadNotes();
            this.dispatchEvent(new RefreshEvent());
            this.toastPersist(shouldSign);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    toastPersist(shouldSign) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: shouldSign ? 'Note signed' : 'Draft saved',
                message: shouldSign
                    ? 'The note is signed and locked.'
                    : 'The note was saved as a draft.',
                variant: 'success'
            })
        );
    }

    async loadNotes() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const states = await getNotes({ encounterId: this._recordId });
            this.notes = (states || []).map((state) => this.toNoteCard(state));
        } catch (error) {
            this.notes = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    toNoteCard(state) {
        const status = state?.status || 'Draft';
        const noteType = state?.noteType || 'Progress Note';
        const body = this.toPlainText(state?.body || '');
        const isLocked = status === 'Signed';
        return {
            id: state?.noteId,
            noteType,
            body,
            status,
            signedDate: state?.signedDate,
            summaryLabel: `${noteType} · ${status}`,
            isLocked,
            canEdit: !isLocked,
            hasBody: !!body
        };
    }

    updateNoteCard(noteId, fields) {
        this.notes = this.notes.map((note) => {
            if (!this.sameRecordId(note.id, noteId)) {
                return note;
            }
            const next = { ...note, ...fields };
            next.summaryLabel = `${next.noteType} · ${next.status}`;
            next.hasBody = !!(next.body && String(next.body).trim());
            return next;
        });
    }

    applyState(state) {
        this.noteId = state?.noteId;
        this.noteType = state?.noteType || 'Progress Note';
        this.body = this.toPlainText(state?.body || '');
        this.status = state?.status || 'Draft';
        this.signedDate = state?.signedDate;
    }

    inlineEditor(noteId) {
        return this.template.querySelector(`lightning-textarea[data-note-id="${noteId}"]`);
    }

    inlineBody(noteId) {
        const editor = this.inlineEditor(noteId);
        if (editor && editor.value != null) {
            return editor.value;
        }
        const card = this.notes.find((note) => this.sameRecordId(note.id, noteId));
        return card ? card.body : '';
    }

    inlineNoteType(noteId) {
        const combobox = this.template.querySelector(`lightning-combobox[data-note-id="${noteId}"]`);
        if (combobox && combobox.value) {
            return combobox.value;
        }
        const card = this.notes.find((note) => this.sameRecordId(note.id, noteId));
        return card ? card.noteType : 'Progress Note';
    }

    currentBody() {
        const editor = this.template.querySelector('[data-id="note-body"]');
        if (editor && editor.value != null) {
            return editor.value;
        }
        return this.body || '';
    }

    insertText(snippet) {
        if (!snippet) {
            return;
        }
        this.syncBody(this.mergeText(this.body, snippet));
    }

    syncBody(nextBody) {
        this.body = nextBody;
        const editor = this.template.querySelector('[data-id="note-body"]');
        if (editor) {
            editor.value = nextBody;
        }
    }

    mergeText(current, snippet) {
        const left = (current || '').replace(/\s+$/, '');
        const right = (snippet || '').replace(/^\s+/, '');
        if (!left) {
            return right;
        }
        if (!right) {
            return left;
        }
        return `${left}\n\n${right}`;
    }

    expandShortcuts(text) {
        let result = text;
        for (const row of this.shortcuts) {
            const shortcut = this.templateValue(row, 'Shortcut__c');
            const escaped = shortcut.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const matcher = new RegExp(escaped + '(?![\\w])');
            if (matcher.test(result)) {
                result = result.replace(matcher, this.toPlainText(this.templateValue(row, 'Body__c')));
                break;
            }
        }
        return result;
    }

    templateValue(row, fieldName) {
        if (!row || !fieldName) {
            return undefined;
        }
        const aliases = {
            Id: ['id', 'Id'],
            Name: ['name', 'Name'],
            Body__c: ['body', 'Body__c', 'lfemr__Body__c'],
            Category__c: ['category', 'Category__c', 'lfemr__Category__c'],
            Shortcut__c: ['shortcut', 'Shortcut__c', 'lfemr__Shortcut__c']
        };
        const keys = aliases[fieldName] || [fieldName, `lfemr__${fieldName}`];
        for (const key of keys) {
            if (row[key] != null) {
                return row[key];
            }
        }
        return undefined;
    }

    toPlainText(value) {
        if (!value) {
            return '';
        }
        const html = String(value);
        if (html.indexOf('<') === -1) {
            return html;
        }
        const withBreaks = html
            .replace(/<br\s*\/?>/gi, '\n')
            .replace(/<\/p>/gi, '\n')
            .replace(/<\/div>/gi, '\n')
            .replace(/<\/h[1-6]>/gi, '\n')
            .replace(/<\/tr>/gi, '\n')
            .replace(/<li[^>]*>/gi, '• ')
            .replace(/<\/li>/gi, '\n');
        const doc = new DOMParser().parseFromString(withBreaks, 'text/html');
        return (doc.body.textContent || '')
            .replace(/\u00a0/g, ' ')
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
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
