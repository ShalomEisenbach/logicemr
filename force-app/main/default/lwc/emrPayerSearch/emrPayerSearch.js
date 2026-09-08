import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import searchPayers from '@salesforce/apex/PayerSearchController.searchPayers';
import getPayer from '@salesforce/apex/PayerSearchController.getPayer';
import savePayerIdentifier from '@salesforce/apex/PayerSearchController.savePayerIdentifier';

const DEBOUNCE_MS = 300;

export default class EmrPayerSearch extends LightningElement {
    _recordId;
    currentIdentifier;
    payerName;
    matches = [];
    errorMessage;
    successMessage;
    isLoading = false;
    isSaving = false;
    hasSearched = false;
    searchTerm = '';
    debounceTimer;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && value) {
            this.loadPayer();
        }
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    get hasMatches() {
        return this.matches && this.matches.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.hasMatches && !this.errorMessage && !this.isLoading;
    }

    get identifierLabel() {
        return this.currentIdentifier
            ? `Current Stedi payer id: ${this.currentIdentifier}`
            : 'No Stedi payer id is set. Eligibility cannot run until one is selected.';
    }

    async loadPayer() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const payer = await getPayer({ payerId: this._recordId });
            this.payerName = payer?.Name || '';
            this.currentIdentifier = payer?.Payer_Identifier__c || '';
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        window.clearTimeout(this.debounceTimer);
    }

    handleSearchChange(event) {
        window.clearTimeout(this.debounceTimer);
        this.searchTerm = event.target.value;
        this.successMessage = undefined;
        this.debounceTimer = window.setTimeout(() => {
            this.runSearch(this.searchTerm);
        }, DEBOUNCE_MS);
    }

    async runSearch(searchTerm) {
        const trimmed = searchTerm ? searchTerm.trim() : '';
        if (!trimmed) {
            this.matches = [];
            this.hasSearched = false;
            this.errorMessage = undefined;
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const rows = await searchPayers({ query: trimmed });
            this.matches = (rows || []).map((row, index) => ({
                key: `${row.payerId || 'payer'}-${index}`,
                payerId: row.payerId,
                name: row.name || row.payerId,
                detail: row.payerId ? `Stedi id: ${row.payerId}` : 'No Stedi id'
            }));
            this.errorMessage = undefined;
        } catch (error) {
            this.matches = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
            this.hasSearched = true;
        }
    }

    async handleSelect(event) {
        const stediPayerId = event.currentTarget.dataset.payerId;
        if (!this._recordId || !stediPayerId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            const saved = await savePayerIdentifier({
                payerId: this._recordId,
                stediPayerId
            });
            this.currentIdentifier = saved?.Payer_Identifier__c || stediPayerId;
            this.successMessage = `Saved Stedi payer id ${this.currentIdentifier}.`;
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
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
        return error?.message || 'Unable to search payers.';
    }
}
