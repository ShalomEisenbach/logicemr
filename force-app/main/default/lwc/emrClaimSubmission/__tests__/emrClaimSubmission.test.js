import { createElement } from 'lwc';
import EmrClaimSubmission from 'c/emrClaimSubmission';
import getSubmissions from '@salesforce/apex/ClaimSubmissionController.getSubmissions';

jest.mock(
    '@salesforce/apex/ClaimSubmissionController.getSubmissions',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/ClaimSubmissionController.queueSubmission', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ClaimSubmissionController.retrySubmission', () => ({ default: jest.fn() }), {
    virtual: true
});

const flushPromises = () => Promise.resolve();

describe('c-emr-claim-submission', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('renders submission state and blocks duplicate submission', async () => {
        const element = createElement('c-emr-claim-submission', { is: EmrClaimSubmission });
        element.superbillId = 'a10000000000001';
        element.claimStatus = 'Ready';
        document.body.appendChild(element);
        getSubmissions.emit([
            {
                Id: 'a20000000000001',
                Name: 'CLMSUB-00000001',
                Status__c: 'Submitted',
                Attempt_Number__c: 1,
                Patient_Control_Number__c: 'ABC123',
                Provider_Used__c: 'Stedi',
                Correlation_Id__c: 'corr-1'
            }
        ]);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('Submitted');
        expect(element.shadowRoot.textContent).toContain('corr-1');
        const submit = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Submit 837P'
        );
        expect(submit.disabled).toBe(true);
    });
});
