import { createElement } from "lwc";
import EmrClaimReadiness from "c/emrClaimReadiness";
import getWorkspace from "@salesforce/apex/ClaimReadinessController.getWorkspace";
import initializeSuperbill from "@salesforce/apex/ClaimReadinessController.initializeSuperbill";
import getCanonicalJson from "@salesforce/apex/ClaimExportController.getCanonicalJson";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/schema/Superbill__c",
  () => ({ default: { objectApiName: "lfemr__Superbill__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Superbill_Diagnosis__c",
  () => ({ default: { objectApiName: "lfemr__Superbill_Diagnosis__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Charge_Line__c",
  () => ({ default: { objectApiName: "lfemr__Charge_Line__c" } }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({
    refreshApex: jest.fn().mockResolvedValue()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ClaimReadinessController.getWorkspace",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.initializeSuperbill",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.refreshClaimSnapshots",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.updateClaimDetails",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.saveCharge",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.deleteCharge",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.markReady",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.reopen",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimReadinessController.quoteRate",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimExportController.getCanonicalJson",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flushPromises = () => Promise.resolve();

describe("c-emr-claim-readiness", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("initializes a superbill from the empty state", async () => {
    initializeSuperbill.mockResolvedValue({
      encounterStatus: "Finished",
      superbill: {
        Id: "a10000000000001",
        Name: "SB-00000001",
        Status__c: "Needs Review"
      },
      diagnoses: [],
      charges: [],
      issues: ["At least one charge line is required."],
      totalCharges: 0,
      canOverrideRates: false
    });
    const element = createElement("c-emr-claim-readiness", {
      is: EmrClaimReadiness
    });
    element.recordId = "a02000000000001";
    document.body.appendChild(element);
    getWorkspace.emit({
      encounterStatus: "Finished",
      superbill: null,
      diagnoses: [],
      charges: [],
      issues: ["Initialize a superbill for this encounter."],
      totalCharges: 0,
      canOverrideRates: false
    });
    await flushPromises();

    const initializeButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Initialize superbill");
    initializeButton.click();
    await flushPromises();
    await flushPromises();

    expect(initializeSuperbill).toHaveBeenCalledWith({
      encounterId: "a02000000000001"
    });
    expect(element.shadowRoot.textContent).toContain(
      "At least one charge line is required."
    );
  });

  it("flags unlinked charges for review without removing or blocking manual lines", async () => {
    const element = createElement("c-emr-claim-readiness", {
      is: EmrClaimReadiness
    });
    element.recordId = "a02000000000003";
    document.body.appendChild(element);
    getWorkspace.emit({
      superbill: { Id: "bill", Status__c: "Needs Review" },
      charges: [
        {
          Id: "linked",
          Procedure__c: "source",
          Source_Procedure_Key__c: "source"
        },
        { Id: "deleted", Source_Procedure_Key__c: "removed-source" },
        { Id: "manual" }
      ],
      diagnoses: [],
      issues: []
    });
    await flushPromises();

    const chargeTable = element.shadowRoot.querySelector("lightning-datatable");
    expect(chargeTable.data.map((row) => row.origin)).toEqual([
      "Procedure",
      "Source removed",
      "Manual / unlinked"
    ]);
    expect(element.shadowRoot.textContent).toContain(
      "Review Manual / unlinked charges before approving"
    );
    const markReady = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Mark claim ready");
    expect(markReady.disabled).toBe(false);
  });

  it("renders namespaced Apex SObjects with Ready submission controls and charge details", async () => {
    const element = createElement("c-emr-claim-readiness", {
      is: EmrClaimReadiness
    });
    element.recordId = "bill";
    document.body.appendChild(element);
    getWorkspace.emit({
      superbill: {
        Id: "bill",
        Name: "SB-1",
        lfemr__Status__c: "Ready",
        lfemr__Patient_First_Name__c: "Ana"
      },
      diagnoses: [
        {
          Id: "diagnosis",
          lfemr__Sequence__c: 1,
          lfemr__Diagnosis_Code__c: "J06.9"
        }
      ],
      charges: [
        {
          Id: "charge",
          lfemr__Procedure_Code__c: "99213",
          lfemr__Units__c: 2,
          lfemr__Charge_Amount__c: 350
        }
      ],
      issues: [],
      totalCharges: 350
    });
    await flushPromises();
    const tables = element.shadowRoot.querySelectorAll("lightning-datatable");
    expect(tables[0].data[0].code).toBe("J06.9");
    expect(tables[1].data[0]).toEqual(
      expect.objectContaining({ code: "99213", units: 2, chargeAmount: 350 })
    );
    expect(
      element.shadowRoot.querySelector("c-emr-claim-submission").claimStatus
    ).toBe("Ready");
    expect(
      [...element.shadowRoot.querySelectorAll("lightning-button")].some(
        (button) => button.label === "Reopen review"
      )
    ).toBe(true);
  });

  it("renders a ready superbill with diagnoses and charges", async () => {
    getCanonicalJson.mockResolvedValue('{"schemaVersion":"1.1"}');
    const element = createElement("c-emr-claim-readiness", {
      is: EmrClaimReadiness
    });
    element.recordId = "a02000000000002";
    document.body.appendChild(element);
    getWorkspace.emit({
      encounterStatus: "Finished",
      superbill: {
        Id: "a10000000000002",
        Name: "SB-00000002",
        Status__c: "Ready",
        Date_of_Service__c: "2026-09-15",
        Place_of_Service_Code__c: "11",
        Coverage__r: { Payer__r: { Name: "Test Payer" } },
        Snapshot_Version__c: 2,
        Snapshot_Refreshed_At__c: "2026-09-15T14:30:00.000Z",
        Patient_First_Name__c: "Jamie",
        Patient_Last_Name__c: "Patient",
        Patient_Date_of_Birth__c: "1985-05-12",
        Patient_Sex__c: "Female",
        Subscriber_First_Name__c: "Jamie",
        Subscriber_Last_Name__c: "Patient",
        Subscriber_Relationship__c: "Self",
        Subscriber_Member_Id__c: "MEMBER-1",
        Payer_Name__c: "Test Payer",
        Payer_Identifier__c: "PAYER-1",
        Claim_Filing_Code__c: "CI",
        Rendering_Provider_Name__c: "Pat Provider",
        Rendering_Provider_NPI__c: "1999999984",
        Rendering_Provider_Taxonomy__c: "207Q00000X",
        Billing_Provider_Name__c: "Logic Clinic",
        Billing_Provider_NPI__c: "1888888875",
        Billing_Provider_EIN__c: "12-3456789",
        Billing_Provider_Street__c: "100 Clinic Ave",
        Billing_Provider_City__c: "Boston",
        Billing_Provider_State__c: "MA",
        Billing_Provider_Postal_Code__c: "02108"
      },
      diagnoses: [
        {
          Id: "a11000000000001",
          Sequence__c: 1,
          Diagnosis_Type__c: "Principal",
          Diagnosis_Code__c: "J06.9",
          Diagnosis_Display__c: "Acute URI"
        }
      ],
      charges: [
        {
          Id: "a12000000000001",
          Procedure_Code_System__c: "CPT",
          Procedure_Code__c: "99213",
          Procedure_Display__c: "Office visit",
          Service_Date__c: "2026-09-15",
          Units__c: 1,
          Charge_Amount__c: 175,
          Diagnosis_Pointers__c: "1",
          Rate_Source__c: "Commercial 2026 - 2026-01-01 to 2026-12-31",
          Rate_Override__c: false
        }
      ],
      issues: [],
      totalCharges: 175,
      ready: true,
      canOverrideRates: false
    });
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "All claim-readiness checks pass."
    );
    expect(element.shadowRoot.textContent).toContain("Pat Provider");
    expect(element.shadowRoot.textContent).toContain("Version 2");
    expect(
      element.shadowRoot.querySelectorAll("lightning-datatable")
    ).toHaveLength(2);
    const chargeTable = element.shadowRoot.querySelectorAll(
      "lightning-datatable"
    )[1];
    expect(chargeTable.columns.some((column) => column.type === "action")).toBe(
      false
    );
    chargeTable.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "edit" }, row: { id: "a12000000000001" } }
      })
    );
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();

    const submission = element.shadowRoot.querySelector(
      "c-emr-claim-submission"
    );
    submission.dispatchEvent(new CustomEvent("claimstatuschanged"));
    await flushPromises();
    expect(refreshApex).toHaveBeenCalled();
    const refreshSnapshotsButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Refresh snapshots");
    expect(refreshSnapshotsButton.disabled).toBe(true);
    const previewButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Preview canonical export");
    previewButton.click();
    await flushPromises();
    await flushPromises();
    expect(getCanonicalJson).toHaveBeenCalledWith({
      superbillId: "a10000000000002"
    });
    expect(element.shadowRoot.querySelector("lightning-textarea").value).toBe(
      '{"schemaVersion":"1.1"}'
    );
    const reopenButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.label === "Reopen review");
    expect(reopenButton).toBeTruthy();
  });
});
