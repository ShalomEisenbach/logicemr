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
    @api layout = 'stack';

    sections = [];
    errorMessage;
    hasLoaded = false;
    medicationsExpanded = false;
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

    get isGrid() {
        return this.layout === 'grid';
    }

    get stackClass() {
        return this.isGrid ? 'summary-stack summary-stack_grid' : 'summary-stack';
    }

    get displaySections() {
        return (this.sections || []).map((section) => {
            const items = section.items || [];
            const overflow = Math.max(0, (section.totalCount || 0) - items.length);
            const variant = section.variant || this.variantFor(section.key);
            const isList = variant === 'list';
            const isMetrics = variant === 'metrics';
            const hasItems = items.length > 0;
            const isCollapsible = section.key === 'medications' && hasItems;
            const isExpanded = !isCollapsible || this.medicationsExpanded;
            const itemCount = section.totalCount || items.length;
            return {
                key: section.key,
                label: section.label,
                emptyLabel: section.emptyLabel,
                hasItems,
                isList,
                isMetrics,
                isCollapsible,
                isExpanded,
                showBody: !isCollapsible || this.medicationsExpanded,
                countLabel: isCollapsible ? String(itemCount) : '',
                toggleIcon: this.medicationsExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                toggleLabel: this.medicationsExpanded
                    ? `Collapse medications, ${itemCount}`
                    : `Expand medications, ${itemCount}`,
                overflowLabel: overflow > 0 && isExpanded ? `+${overflow} more` : '',
                stripClass: this.stripClassFor(section.tone, variant, isCollapsible && !this.medicationsExpanded),
                role: section.tone === 'high' ? 'alert' : 'status',
                iconName: ICON_BY_TONE[section.tone] || '',
                iconVariant: ICON_VARIANT_BY_TONE[section.tone] || 'inverse',
                showIcon: Boolean(ICON_BY_TONE[section.tone]),
                items: items.map((item) => this.toDisplayItem(item, variant, this.isGrid))
            };
        });
    }

    variantFor(key) {
        if (key === 'medications') {
            return 'list';
        }
        if (key === 'flowsheet') {
            return 'metrics';
        }
        return 'chips';
    }

    toDisplayItem(item, variant, compact) {
        const flag = item.flag;
        const flagKey = (flag || '').toLowerCase();
        return {
            id: item.id,
            name: item.name,
            objectApiName: item.objectApiName,
            flag,
            title: item.title || item.flag || item.name,
            detail: item.detail,
            unit: item.unit,
            displayValue: item.value || item.name,
            emphasize: item.emphasize === true,
            showFlag: Boolean(flag),
            showDetail: !compact && variant === 'list' && Boolean(item.detail) && item.detail !== item.name,
            cssClass: item.emphasize ? 'summary-chip summary-chip_emphasis' : 'summary-chip',
            valueClass: this.metricValueClass(flagKey),
            flagClass: this.metricFlagClass(flagKey)
        };
    }

    metricValueClass(flagKey) {
        if (flagKey === 'critical' || flagKey === 'high') {
            return 'metric-value metric-value_high';
        }
        if (flagKey === 'low') {
            return 'metric-value metric-value_low';
        }
        if (flagKey === 'abnormal') {
            return 'metric-value metric-value_abnormal';
        }
        return 'metric-value';
    }

    metricFlagClass(flagKey) {
        if (flagKey === 'critical' || flagKey === 'high') {
            return 'metric-flag metric-flag_high';
        }
        if (flagKey === 'low') {
            return 'metric-flag metric-flag_low';
        }
        return 'metric-flag';
    }

    handleToggleMedications() {
        this.medicationsExpanded = !this.medicationsExpanded;
    }

    stripClassFor(tone, variant, collapsed) {
        const stacked = variant === 'list' || variant === 'metrics' ? ' alert-strip_stack' : '';
        const compact = collapsed ? ' alert-strip_collapsed' : '';
        switch (tone) {
            case 'high':
                return `alert-strip alert-strip_high${stacked}${compact}`;
            case 'warning':
                return `alert-strip alert-strip_warning${stacked}${compact}`;
            case 'success':
                return `alert-strip alert-strip_success${stacked}${compact}`;
            case 'attention':
                return `alert-strip alert-strip_attention${stacked}${compact}`;
            case 'info':
                return `alert-strip alert-strip_info${stacked}${compact}`;
            default:
                return `alert-strip alert-strip_empty${stacked}${compact}`;
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
