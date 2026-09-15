import { createElement } from 'lwc';
import EmrClaimReadiness from 'c/emrClaimReadiness';
import getWorkspace from '@salesforce/apex/ClaimReadinessController.getWorkspace';
import initializeSuperbill from '@salesforce/apex/ClaimReadinessController.initializeSuperbill';

jest.mock(
    '@salesforce/apex/ClaimReadinessController.getWorkspace',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ClaimReadinessController.initializeSuperbill',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/apex/ClaimReadinessController.saveCharge', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ClaimReadinessController.deleteCharge', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ClaimReadinessController.markReady', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ClaimReadinessController.reopen', () => ({ default: jest.fn() }), {
    virtual: true
});

const flushPromises = () => Promise.resolve();

describe('c-emr-claim-readiness', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('initializes a superbill from the empty state', async () => {
        initializeSuperbill.mockResolvedValue({
            encounterStatus: 'Finished',
            superbill: { Id: 'a10000000000001', Name: 'SB-00000001', Status__c: 'Needs Review' },
            diagnoses: [],
            charges: [],
            issues: ['At least one charge line is required.'],
            totalCharges: 0
        });
        const element = createElement('c-emr-claim-readiness', { is: EmrClaimReadiness });
        element.recordId = 'a02000000000001';
        document.body.appendChild(element);
        getWorkspace.emit({
            encounterStatus: 'Finished',
            superbill: null,
            diagnoses: [],
            charges: [],
            issues: ['Initialize a superbill for this encounter.'],
            totalCharges: 0
        });
        await flushPromises();

        const initializeButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Initialize superbill'
        );
        initializeButton.click();
        await flushPromises();
        await flushPromises();

        expect(initializeSuperbill).toHaveBeenCalledWith({ encounterId: 'a02000000000001' });
        expect(element.shadowRoot.textContent).toContain('At least one charge line is required.');
    });

    it('renders a ready superbill with diagnoses and charges', async () => {
        const element = createElement('c-emr-claim-readiness', { is: EmrClaimReadiness });
        element.recordId = 'a02000000000002';
        document.body.appendChild(element);
        getWorkspace.emit({
            encounterStatus: 'Finished',
            superbill: {
                Id: 'a10000000000002',
                Name: 'SB-00000002',
                Status__c: 'Ready',
                Date_of_Service__c: '2026-09-15',
                Coverage__r: { Payer__r: { Name: 'Test Payer' } }
            },
            diagnoses: [
                {
                    Id: 'a11000000000001',
                    Sequence__c: 1,
                    Diagnosis_Type__c: 'Principal',
                    Diagnosis_Code__c: 'J06.9',
                    Diagnosis_Display__c: 'Acute URI'
                }
            ],
            charges: [
                {
                    Id: 'a12000000000001',
                    Procedure_Code_System__c: 'CPT',
                    Procedure_Code__c: '99213',
                    Procedure_Display__c: 'Office visit',
                    Service_Date__c: '2026-09-15',
                    Units__c: 1,
                    Charge_Amount__c: 175,
                    Diagnosis_Pointers__c: '1'
                }
            ],
            issues: [],
            totalCharges: 175,
            ready: true
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('All claim-readiness checks pass.');
        expect(element.shadowRoot.querySelectorAll('lightning-datatable')).toHaveLength(2);
        const reopenButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Reopen review'
        );
        expect(reopenButton).toBeTruthy();
    });
});
