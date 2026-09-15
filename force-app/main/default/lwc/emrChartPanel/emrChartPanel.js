import { LightningElement, api } from 'lwc';

/**
 * Reusable Patient Chart panel shell.
 *
 * Use this as the outer frame for every clinical chart panel (encounters,
 * problems, meds, allergies, etc.). Do not drop emrChartPanel on a Lightning
 * page by itself — wrap it in a feature LWC that supplies data and actions.
 *
 * Public API
 * - title (String): header text
 * - count (Number, optional): appends the record count to the header text
 * - viewAllLabel (String, optional): when set with hasRecords, View All is shown under the table
 * - hasRecords (Boolean): View All is shown only when true
 * - collapsible (Boolean): shows a control that independently expands or collapses the panel
 * - expanded (Boolean): initial and externally controlled expanded state; defaults to true
 * - viewall event: fired when View All is clicked
 * - actions slot: optional header buttons (Add) on the top right
 * - default slot: panel body
 *
 * Example — later panels should follow emrEncounterPanel:
 *
 *   <c-emr-chart-panel
 *       title="Problems"
 *       view-all-label="View All"
 *       onviewall={handleViewAll}
 *   >
 *       <lightning-datatable ...></lightning-datatable>
 *   </c-emr-chart-panel>
 *
 * handleViewAll() navigates or opens a related list. Leave view-all-label
 * unset, or pass has-records={false}, to hide the action.
 */
export default class EmrChartPanel extends LightningElement {
    @api title;
    @api count;
    @api viewAllLabel;
    @api hasRecords = false;
    @api collapsible = false;

    _isExpanded = true;

    @api
    get expanded() {
        return this._isExpanded;
    }

    set expanded(value) {
        this._isExpanded = value !== false && value !== 'false';
    }

    get isExpanded() {
        return !this.collapsible || this._isExpanded;
    }

    get displayTitle() {
        return this.count === undefined || this.count === null || this.count === ''
            ? this.title
            : `${this.title} (${this.count})`;
    }

    get toggleIconName() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get toggleLabel() {
        return this.isExpanded ? `Collapse ${this.displayTitle}` : `Expand ${this.displayTitle}`;
    }

    get showViewAll() {
        return !!this.viewAllLabel && this.hasRecords;
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewall'));
    }

    handleToggle() {
        this._isExpanded = !this._isExpanded;
        this.dispatchEvent(
            new CustomEvent('toggle', {
                detail: { expanded: this._isExpanded }
            })
        );
    }
}
