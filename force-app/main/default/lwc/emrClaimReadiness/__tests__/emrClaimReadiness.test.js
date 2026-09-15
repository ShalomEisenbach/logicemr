import { createElement } from 'lwc';
import EmrClaimReadiness from 'c/emrClaimReadiness';
import getWorkspace from '@salesforce/apex/ClaimReadinessController.getWorkspace';
import initializeSuperbill from '@salesforce/apex/ClaimReadinessController.initializeSuperbill';
import getCanonicalJson from '@salesforce/apex/ClaimExportController.getCanonicalJson';

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
jest.mock('@salesforce/apex/ClaimReadinessController.refreshClaimSnapshots', () => ({ default: jest.fn() }), {
    virtual: true
});
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
jest.mock('@salesforce/apex/ClaimReadinessController.quoteRate', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ClaimExportController.getCanonicalJson', () => ({ default: jest.fn() }), {
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
            totalCharges: 0,
            canOverrideRates: false
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
            totalCharges: 0,
            canOverrideRates: false
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
        getCanonicalJson.mockResolvedValue('{"schemaVersion":"1.0"}');
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
                Coverage__r: { Payer__r: { Name: 'Test Payer' } },
                Snapshot_Version__c: 2,
                Snapshot_Refreshed_At__c: '2026-09-15T14:30:00.000Z',
                Patient_First_Name__c: 'Jamie',
                Patient_Last_Name__c: 'Patient',
                Patient_Date_of_Birth__c: '1985-05-12',
                Patient_Sex__c: 'Female',
                Subscriber_First_Name__c: 'Jamie',
                Subscriber_Last_Name__c: 'Patient',
                Subscriber_Relationship__c: 'Self',
                Subscriber_Member_Id__c: 'MEMBER-1',
                Payer_Name__c: 'Test Payer',
                Payer_Identifier__c: 'PAYER-1',
                Rendering_Provider_Name__c: 'Pat Provider',
                Rendering_Provider_NPI__c: '1999999984',
                Rendering_Provider_Taxonomy__c: '207Q00000X',
                Billing_Provider_Name__c: 'Logic Clinic',
                Billing_Provider_NPI__c: '1888888875',
                Billing_Provider_EIN__c: '12-3456789',
                Billing_Provider_Street__c: '100 Clinic Ave',
                Billing_Provider_City__c: 'Boston',
                Billing_Provider_State__c: 'MA',
                Billing_Provider_Postal_Code__c: '02108'
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
                    Diagnosis_Pointers__c: '1',
                    Rate_Source__c: 'Commercial 2026 - 2026-01-01 to 2026-12-31',
                    Rate_Override__c: false
                }
            ],
            issues: [],
            totalCharges: 175,
            ready: true,
            canOverrideRates: false
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('All claim-readiness checks pass.');
        expect(element.shadowRoot.textContent).toContain('Pat Provider');
        expect(element.shadowRoot.textContent).toContain('Version 2');
        expect(element.shadowRoot.querySelectorAll('lightning-datatable')).toHaveLength(2);
        const refreshSnapshotsButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Refresh snapshots'
        );
        expect(refreshSnapshotsButton.disabled).toBe(true);
        const previewButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Preview canonical export'
        );
        previewButton.click();
        await flushPromises();
        await flushPromises();
        expect(getCanonicalJson).toHaveBeenCalledWith({ superbillId: 'a10000000000002' });
        expect(element.shadowRoot.querySelector('lightning-textarea').value).toBe('{"schemaVersion":"1.0"}');
        const reopenButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.label === 'Reopen review'
        );
        expect(reopenButton).toBeTruthy();
    });
});
