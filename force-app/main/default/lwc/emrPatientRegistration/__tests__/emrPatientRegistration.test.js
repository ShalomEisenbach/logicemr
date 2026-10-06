import { createElement } from "lwc";
import EmrPatientRegistration from "c/emrPatientRegistration";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import registerPatient from "@salesforce/apex/PatientRegistrationController.registerPatient";
import updatePatientDemographics from "@salesforce/apex/PatientRegistrationController.updatePatientDemographics";
import getPatientDemographics from "@salesforce/apex/PatientRegistrationController.getPatientDemographics";
import getCoverages from "@salesforce/apex/CoveragePanelController.getCoverages";
import saveCoverageDetails from "@salesforce/apex/CoveragePanelController.saveCoverageDetails";
import runCheck from "@salesforce/apex/EligibilityCheckController.runCheck";

jest.mock(
  "@salesforce/schema/Patient__c",
  () => ({ default: { objectApiName: "lfemr__Patient__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Coverage__c",
  () => ({ default: { objectApiName: "lfemr__Coverage__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/LogicEMR_Run_Eligibility",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PatientRegistrationController.registerPatient",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PatientRegistrationController.updatePatientDemographics",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PatientRegistrationController.getPatientDemographics",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoveragePanelController.getCoverages",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoveragePanelController.saveCoverageDetails",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EligibilityCheckController.runCheck",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i += 1) {
    // Flush nested Apex promises and LWC rendering.
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
const fields = (values) =>
  Object.fromEntries(
    Object.entries(values).map(([key, value]) => [`lfemr__${key}`, value])
  );
const activeCoverage = {
  Id: "coverage-primary",
  ...fields({
    Payer__c: "payer1",
    Member_Id__c: "M1",
    Group_Number__c: "G1",
    Plan_Name__c: "Existing plan",
    Type__c: "Medical",
    Status__c: "Active",
    Priority__c: "Primary",
    Effective_Start__c: "2026-01-01",
    Effective_End__c: "2026-12-31",
    Relationship_to_Subscriber__c: "Self",
    Subscriber_Name__c: "Ana Rivera",
    Member_ID_Identifies_Patient__c: true,
    Subscriber_First_Name__c: "Ana",
    Subscriber_Last_Name__c: "Rivera",
    Subscriber_Date_of_Birth__c: "1980-02-03",
    Subscriber_Sex__c: "Female",
    Subscriber_Street__c: "20 Main St",
    Subscriber_City__c: "Boston",
    Subscriber_State__c: "MA",
    Subscriber_Postal_Code__c: "02108",
    Subscriber_Country__c: "US"
  })
};

function controlFor(element, name) {
  return [
    ...element.shadowRoot.querySelectorAll(
      "lightning-input, lightning-combobox"
    )
  ].find((item) => item.name === name);
}

function input(element, name, value) {
  const control = controlFor(element, name);
  if (control.type === "checkbox") {
    control.checked = value;
  } else {
    control.value = value;
  }
  control.dispatchEvent(new CustomEvent("change"));
}

async function save(element) {
  for (const control of element.shadowRoot.querySelectorAll(
    "lightning-input, lightning-combobox"
  )) {
    control.reportValidity = jest.fn(() => true);
  }
  const button = [
    ...element.shadowRoot.querySelectorAll("lightning-button")
  ].find((item) => item.variant === "brand");
  button.click();
  await flush();
}

async function create() {
  const element = createElement("c-emr-patient-registration", {
    is: EmrPatientRegistration
  });
  document.body.appendChild(element);
  getObjectInfo.emit({ createable: true, updateable: true });
  await flush();
  return element;
}

describe("patient registration insurance and retry", () => {
  beforeEach(() => {
    getPatientDemographics.mockResolvedValue({
      Id: "patient1",
      ...fields({
        MRN__c: "MRN1",
        Last_Name__c: "Rivera",
        First_Name__c: "Ana"
      })
    });
    getCoverages.mockResolvedValue([{ coverage: activeCoverage }]);
    updatePatientDemographics.mockResolvedValue({ Id: "patient1" });
    registerPatient.mockResolvedValue({
      patient: { Id: "patient-new" },
      duplicates: []
    });
    saveCoverageDetails.mockResolvedValue({ Id: "coverage-new" });
    runCheck.mockResolvedValue({ Id: "check1" });
  });

  afterEach(() => {
    document.body.replaceChildren();
    jest.resetAllMocks();
  });

  it("loads namespaced demographics and leaves insurance untouched during a phone edit", async () => {
    const element = await create();
    await element.openForEdit("patient1");
    await flush();
    expect(
      [...element.shadowRoot.querySelectorAll("lightning-input")].find(
        (item) => item.name === "lastName"
      ).value
    ).toBe("Rivera");
    input(element, "phone", "5551234567");
    await save(element);
    expect(updatePatientDemographics).toHaveBeenCalledWith({
      input: expect.objectContaining({
        patientId: "patient1",
        phone: "5551234567"
      })
    });
    expect(saveCoverageDetails).not.toHaveBeenCalled();
    expect(runCheck).not.toHaveBeenCalled();
  });

  it("selects active primary medical coverage and preserves undisplayed fields when edited", async () => {
    getCoverages.mockResolvedValue([
      {
        coverage: {
          Id: "inactive",
          ...fields({
            Type__c: "Medical",
            Status__c: "Inactive",
            Priority__c: "Primary"
          })
        }
      },
      {
        coverage: {
          Id: "dental",
          ...fields({
            Type__c: "Dental",
            Status__c: "Active",
            Priority__c: "Primary"
          })
        }
      },
      { coverage: activeCoverage }
    ]);
    const element = await create();
    await element.openForEdit("patient1");
    await flush();
    input(element, "memberId", "M2");
    await save(element);
    expect(saveCoverageDetails).toHaveBeenCalledWith({
      input: expect.objectContaining({
        coverageId: "coverage-primary",
        memberId: "M2",
        planName: "Existing plan",
        coverageType: "Medical",
        status: "Active",
        priority: "Primary",
        effectiveStart: "2026-01-01",
        effectiveEnd: "2026-12-31",
        memberIdIdentifiesPatient: true,
        subscriberFirstName: "Ana",
        subscriberLastName: "Rivera",
        subscriberDateOfBirth: "1980-02-03",
        subscriberSex: "Female",
        subscriberStreet: "20 Main St",
        subscriberCity: "Boston",
        subscriberState: "MA",
        subscriberPostalCode: "02108",
        subscriberCountry: "US"
      })
    });
  });

  it("runs explicitly selected eligibility on unchanged existing coverage without rewriting it", async () => {
    const element = await create();
    await element.openForEdit("patient1");
    await flush();
    input(element, "checkEligibility", true);
    await save(element);
    expect(saveCoverageDetails).not.toHaveBeenCalled();
    expect(runCheck).toHaveBeenCalledWith({ coverageId: "coverage-primary" });
  });

  it("reuses saved patient and coverage after eligibility failure", async () => {
    runCheck
      .mockRejectedValueOnce({ body: { message: "Provider unavailable" } })
      .mockResolvedValueOnce({ Id: "check1" });
    const element = await create();
    const created = jest.fn();
    element.addEventListener("patientcreated", created);
    element.open();
    await flush();
    input(element, "mrn", "MRN-NEW");
    input(element, "lastName", "Newpatient");
    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "payer1" } })
      );
    await save(element);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("The patient was registered.");
    await save(element);
    expect(registerPatient).toHaveBeenCalledTimes(1);
    expect(saveCoverageDetails).toHaveBeenCalledTimes(1);
    expect(updatePatientDemographics).toHaveBeenCalledWith({
      input: expect.objectContaining({ patientId: "patient-new" })
    });
    expect(runCheck).toHaveBeenCalledTimes(2);
    expect(created.mock.calls[0][0].detail.patientId).toBe("patient-new");
  });

  it("requires structured policyholder identity when a dependent shares the member ID", async () => {
    const element = await create();
    element.open();
    await flush();
    input(element, "relationshipToSubscriber", "Child");
    await flush();
    const checkbox = controlFor(element, "memberIdIdentifiesPatient");
    expect(checkbox.checked).toBe(true);
    expect(controlFor(element, "subscriberFirstName").required).toBe(false);
    input(element, "memberIdIdentifiesPatient", false);
    await flush();
    expect(controlFor(element, "subscriberFirstName").required).toBe(true);
    await save(element);
    expect(registerPatient).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("policyholder first name");

    input(element, "subscriberFirstName", "Jordan");
    input(element, "subscriberLastName", "Policyholder");
    input(element, "subscriberDateOfBirth", "1975-06-12");
    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "payer1" } })
      );
    await save(element);
    expect(saveCoverageDetails).toHaveBeenCalledWith({
      input: expect.objectContaining({
        patientId: "patient-new",
        relationshipToSubscriber: "Child",
        memberIdIdentifiesPatient: false,
        subscriberFirstName: "Jordan",
        subscriberLastName: "Policyholder",
        subscriberDateOfBirth: "1975-06-12"
      })
    });
  });

  it("loads a dependent policyholder and preserves every hidden subscriber field during an insurance edit", async () => {
    getCoverages.mockResolvedValue([
      {
        coverage: {
          ...activeCoverage,
          ...fields({
            Relationship_to_Subscriber__c: "Spouse",
            Member_ID_Identifies_Patient__c: false
          })
        }
      }
    ]);
    const element = await create();
    await element.openForEdit("patient1");
    await flush();
    expect(controlFor(element, "memberIdIdentifiesPatient").checked).toBe(
      false
    );
    expect(controlFor(element, "subscriberFirstName").value).toBe("Ana");
    input(element, "subscriberFirstName", "Updated");
    await save(element);
    expect(saveCoverageDetails).toHaveBeenCalledWith({
      input: expect.objectContaining({
        coverageId: "coverage-primary",
        memberIdIdentifiesPatient: false,
        subscriberFirstName: "Updated",
        subscriberLastName: "Rivera",
        subscriberDateOfBirth: "1980-02-03",
        subscriberSex: "Female",
        subscriberStreet: "20 Main St",
        subscriberCity: "Boston",
        subscriberState: "MA",
        subscriberPostalCode: "02108",
        subscriberCountry: "US",
        planName: "Existing plan",
        effectiveStart: "2026-01-01",
        effectiveEnd: "2026-12-31"
      })
    });
  });

  it("retries coverage failure without creating the saved patient again", async () => {
    saveCoverageDetails
      .mockRejectedValueOnce({ body: { message: "Coverage unavailable" } })
      .mockResolvedValueOnce({ Id: "coverage-new" });
    const element = await create();
    element.open();
    await flush();
    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "payer1" } })
      );
    await save(element);
    await save(element);
    expect(registerPatient).toHaveBeenCalledTimes(1);
    expect(saveCoverageDetails).toHaveBeenCalledTimes(2);
    expect(saveCoverageDetails.mock.calls[1][0].input.patientId).toBe(
      "patient-new"
    );
    expect(runCheck).toHaveBeenCalledWith({ coverageId: "coverage-new" });
  });

  it("allows demographics save after a coverage read error without offering a duplicate insurance form", async () => {
    getCoverages.mockRejectedValue({ body: { message: "No access" } });
    const element = await create();
    await element.openForEdit("patient1");
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-record-picker")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("Insurance could not be loaded.");
    await save(element);
    expect(updatePatientDemographics).toHaveBeenCalledTimes(1);
    expect(saveCoverageDetails).not.toHaveBeenCalled();
  });
});
