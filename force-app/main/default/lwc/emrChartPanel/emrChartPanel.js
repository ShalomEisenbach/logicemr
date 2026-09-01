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
 * - viewAllLabel (String, optional): when set, a header action is shown
 * - viewall event: fired when the header action is clicked
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
 * unset to hide the action.
 */
export default class EmrChartPanel extends LightningElement {
    @api title;
    @api viewAllLabel;

    get showViewAll() {
        return !!this.viewAllLabel;
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewall'));
    }
}
