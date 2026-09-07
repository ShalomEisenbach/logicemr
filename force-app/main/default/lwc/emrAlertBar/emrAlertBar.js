import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getClinicalSummary from '@salesforce/apex/AlertBarController.getClinicalSummary';

const ICON_BY_TONE = {
    high: 'utility:error',
    warning: 'utility:warning',
    attention: 'utility:info'
};

const ICON_VARIANT_BY_TONE = {
    high: 'error',
    warning: 'warning',
    attention: 'inverse'
};

export default class EmrAlertBar extends LightningElement {
    @api recordId;

    sections = [];
    errorMessage;
    hasLoaded = false;
    wiredSummaryResult;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    refreshHandler() {
        if (!this.wiredSummaryResult) {
            return Promise.resolve();
        }
        return refreshApex(this.wiredSummaryResult);
    }

    @wire(getClinicalSummary, { recordId: '$recordId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.sections = result.data.sections || [];
            this.errorMessage = undefined;
            this.hasLoaded = true;
        } else if (result.error) {
            this.sections = [];
            this.errorMessage = this.reduceError(result.error);
            this.hasLoaded = true;
        }
    }

    get displaySections() {
        return (this.sections || []).map((section) => {
            const items = section.items || [];
            const overflow = Math.max(0, (section.totalCount || 0) - items.length);
            return {
                key: section.key,
                label: section.label,
                emptyLabel: section.emptyLabel,
                hasItems: items.length > 0,
                overflowLabel: overflow > 0 ? `+${overflow} more` : '',
                stripClass: this.stripClassFor(section.tone),
                role: section.tone === 'high' ? 'alert' : 'status',
                iconName: ICON_BY_TONE[section.tone] || '',
                iconVariant: ICON_VARIANT_BY_TONE[section.tone] || 'inverse',
                showIcon: Boolean(ICON_BY_TONE[section.tone]),
                items: items.map((item) => ({
                    id: item.id,
                    name: item.name,
                    objectApiName: item.objectApiName,
                    flag: item.flag,
                    title: item.title || item.flag || item.name,
                    emphasize: item.emphasize === true,
                    showFlag: Boolean(item.flag),
                    cssClass: item.emphasize ? 'summary-chip summary-chip_emphasis' : 'summary-chip'
                }))
            };
        });
    }

    stripClassFor(tone) {
        switch (tone) {
            case 'high':
                return 'alert-strip alert-strip_high';
            case 'warning':
                return 'alert-strip alert-strip_warning';
            case 'success':
                return 'alert-strip alert-strip_success';
            case 'attention':
                return 'alert-strip alert-strip_attention';
            case 'info':
                return 'alert-strip alert-strip_info';
            default:
                return 'alert-strip alert-strip_empty';
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load clinical summary.';
    }
}
