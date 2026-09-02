import { LightningElement, api } from 'lwc';
import searchCodes from '@salesforce/apex/CodeSearchController.search';

const DEBOUNCE_MS = 300;

export default class EmrCodeSearch extends LightningElement {
    @api label = 'Code';
    @api placeholder = 'Search codes';
    @api required = false;
    @api codeSystems = [];
    @api includeRecordId = false;

    inputValue = '';
    results = [];
    errorMessage;
    showDropdown = false;
    hasSearched = false;
    debounceTimer;
    _value;

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
        this.inputValue = this.formatSelection(val);
    }

    @api
    clear() {
        this._value = undefined;
        this.inputValue = '';
        this.results = [];
        this.showDropdown = false;
        this.hasSearched = false;
        this.errorMessage = undefined;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get showNoResults() {
        return this.showDropdown && this.hasSearched && !this.hasResults && !this.errorMessage;
    }

    disconnectedCallback() {
        window.clearTimeout(this.debounceTimer);
    }

    handleInput(event) {
        this.inputValue = event.target.value;
        if (this._value) {
            this._value = undefined;
            this.dispatchSelection('', '', '', undefined);
        }
        window.clearTimeout(this.debounceTimer);
        this.debounceTimer = window.setTimeout(() => {
            this.runSearch(this.inputValue);
        }, DEBOUNCE_MS);
    }

    handleFocus() {
        if (this.hasResults || this.showNoResults || this.errorMessage) {
            this.showDropdown = true;
        }
    }

    handleBlur() {
        this.showDropdown = false;
    }

    handleOptionMouseDown(event) {
        event.preventDefault();
    }

    handleSelect(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.results.find((item) => item.key === key);
        if (!row) {
            return;
        }
        const detail = {
            system: row.system,
            code: row.code,
            display: row.display,
            recordId: row.recordId
        };
        this._value = detail;
        this.inputValue = row.label;
        this.results = [];
        this.showDropdown = false;
        this.hasSearched = false;
        this.errorMessage = undefined;
        this.dispatchSelection(detail.system, detail.code, detail.display, detail.recordId);
    }

    async runSearch(searchTerm) {
        const trimmed = searchTerm ? searchTerm.trim() : '';
        if (!trimmed) {
            this.results = [];
            this.showDropdown = false;
            this.hasSearched = false;
            this.errorMessage = undefined;
            return;
        }

        try {
            const rows = await searchCodes({
                term: trimmed,
                systems: this.normalizedSystems
            });
            this.results = (rows || []).map((row, index) => {
                const system = row.codeSystem || row.system || '';
                const code = row.code || '';
                const display = row.display || '';
                const recordId = row.recordId || row.id || undefined;
                return {
                    key: `${system}-${code}-${index}`,
                    recordId,
                    system,
                    code,
                    display,
                    label: this.formatSelection({ system, code, display })
                };
            });
            this.errorMessage = undefined;
        } catch (error) {
            this.results = [];
            this.errorMessage = this.reduceError(error);
        }
        this.hasSearched = true;
        this.showDropdown = true;
    }

    get normalizedSystems() {
        return Array.isArray(this.codeSystems) ? this.codeSystems.filter((system) => !!system) : [];
    }

    formatSelection(val) {
        if (!val) {
            return '';
        }
        const code = val.code || '';
        const display = val.display || '';
        const system = val.system || '';
        if (!code && !display) {
            return '';
        }
        if (code && display && system) {
            return `${code} — ${display} (${system})`;
        }
        return display || code;
    }

    dispatchSelection(system, code, display, recordId) {
        const detail = { system, code, display };
        if (this.includeRecordId) {
            detail.recordId = recordId;
        }
        this.dispatchEvent(
            new CustomEvent('codeselected', {
                detail
            })
        );
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to search codes.';
    }
}
