import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { recordViewPageRef } from 'c/emrNavigationUtils';

/**
 * Clickable record name that navigates to the record page.
 *
 * Public API
 * - recordId (Id): target record
 * - objectApiName (String): namespaced object API name
 * - label (String): display text
 * - inverse (Boolean): white link text for dark backgrounds
 */
export default class EmrRecordLink extends NavigationMixin(LightningElement) {
    _recordId;
    _objectApiName;
    @api label;
    @api inverse = false;
    @track url;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.resolveUrl();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        this.resolveUrl();
    }

    get showLink() {
        return !!(this._recordId && this._objectApiName && this.url);
    }

    get displayLabel() {
        return this.label || '';
    }

    get linkClass() {
        return this.inverse ? 'record-link record-link_inverse' : 'record-link';
    }

    async resolveUrl() {
        if (!this._recordId || !this._objectApiName) {
            this.url = undefined;
            return;
        }
        try {
            this.url = await this[NavigationMixin.GenerateUrl](
                recordViewPageRef(this._recordId, this._objectApiName)
            );
        } catch (e) {
            this.url = undefined;
        }
    }

    handleClick(event) {
        // Allow ctrl/cmd/middle-click to open in new tab via href.
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1) {
            return;
        }
        event.preventDefault();
        if (!this._recordId || !this._objectApiName) {
            return;
        }
        this[NavigationMixin.Navigate](recordViewPageRef(this._recordId, this._objectApiName));
    }
}
