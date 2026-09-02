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
 * - viewAllLabel (String, optional): when set with hasRecords, View All is shown under the table
 * - hasRecords (Boolean): View All is shown only when true
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
    @api viewAllLabel;
    @api hasRecords = false;

    get showViewAll() {
        return !!this.viewAllLabel && this.hasRecords;
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewall'));
    }
}
