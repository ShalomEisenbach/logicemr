import { createElement } from 'lwc';
import EmrChartPanel from 'c/emrChartPanel';

const flushPromises = () => Promise.resolve();

describe('c-emr-chart-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders an expanded collapsible panel by default', () => {
        const element = createElement('c-emr-chart-panel', { is: EmrChartPanel });
        element.title = 'Appointments';
        element.collapsible = true;
        document.body.appendChild(element);

        const toggle = element.shadowRoot.querySelector('lightning-button-icon');
        expect(toggle).toBeTruthy();
        expect(toggle.alternativeText).toBe('Collapse Appointments');
        expect(element.shadowRoot.querySelector('.slds-card__body')).toBeTruthy();
    });

    it('independently collapses and expands its body', async () => {
        const element = createElement('c-emr-chart-panel', { is: EmrChartPanel });
        element.title = 'Encounters';
        element.collapsible = true;
        document.body.appendChild(element);
        const toggleHandler = jest.fn();
        element.addEventListener('toggle', toggleHandler);

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();

        expect(toggleHandler).toHaveBeenCalledWith(
            expect.objectContaining({ detail: { expanded: false } })
        );
        expect(element.shadowRoot.querySelector('.slds-card__body')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button-icon').alternativeText).toBe(
            'Expand Encounters'
        );

        element.shadowRoot.querySelector('lightning-button-icon').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.slds-card__body')).toBeTruthy();
    });

    it('fires the View All action when records are present', () => {
        const element = createElement('c-emr-chart-panel', { is: EmrChartPanel });
        element.viewAllLabel = 'View All Appointments';
        element.hasRecords = true;
        document.body.appendChild(element);
        const viewAllHandler = jest.fn();
        element.addEventListener('viewall', viewAllHandler);

        element.shadowRoot.querySelector('lightning-button').click();

        expect(viewAllHandler).toHaveBeenCalledTimes(1);
    });
});
