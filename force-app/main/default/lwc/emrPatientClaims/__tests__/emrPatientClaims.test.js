import { createElement } from "lwc";
import EmrPatientClaims from "c/emrPatientClaims";
import getPatientSuperbills from "@salesforce/apex/PatientClaimsController.getPatientSuperbills";

jest.mock(
  "@salesforce/apex/PatientClaimsController.getPatientSuperbills",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flushPromises = (remaining = 10) => {
  if (remaining === 0) {
    return Promise.resolve();
  }
  return Promise.resolve().then(() => flushPromises(remaining - 1));
};

describe("c-emr-patient-claims", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders patient superbills", async () => {
    const element = createElement("c-emr-patient-claims", {
      is: EmrPatientClaims
    });
    element.recordId = "a01000000000001";
    document.body.appendChild(element);

    getPatientSuperbills.emit([
      {
        id: "a10000000000001",
        name: "SB-00000001",
        encounterId: "a02000000000001",
        encounterName: "Encounter 1",
        dateOfService: "2026-09-15",
        status: "Ready",
        renderingPractitionerName: "Ada Provider",
        payerName: "Test Payer",
        totalCharges: 190,
        validationMessages: null
      }
    ]);
    await flushPromises();
    await flushPromises();

    const panel = element.shadowRoot.querySelector("c-emr-chart-panel");
    const table = panel.querySelector("lightning-datatable");
    expect(table).not.toBeNull();
    expect(table.data).toHaveLength(1);
    expect(table.data[0].name).toBe("SB-00000001");
    expect(panel.count).toBe(1);
    expect(panel.textContent).toContain("Ready");
  });

  it("renders the empty state", async () => {
    const element = createElement("c-emr-patient-claims", {
      is: EmrPatientClaims
    });
    element.recordId = "a01000000000002";
    document.body.appendChild(element);

    getPatientSuperbills.emit([]);
    await flushPromises();
    await flushPromises();

    const panel = element.shadowRoot.querySelector("c-emr-chart-panel");
    expect(panel.count).toBe(0);
    expect(panel.textContent).toContain("No superbills.");
  });
});
