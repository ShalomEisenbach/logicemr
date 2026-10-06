import { createElement } from "lwc";
import EmrDiagnosticReportPanel from "c/emrDiagnosticReportPanel";
import getReports from "@salesforce/apex/DiagnosticReportPanelController.getReports";
import addLinkedReport from "@salesforce/apex/DiagnosticReportPanelController.addLinkedReport";

jest.mock(
  "@salesforce/apex/DiagnosticReportPanelController.getReports",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DiagnosticReportPanelController.addLinkedReport",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DiagnosticReportPanelController.deleteReports",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DiagnosticReportService.markReviewed",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn().mockResolvedValue() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/ServiceRequest__c",
  () => ({ default: { objectApiName: "lfemr__ServiceRequest__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/ServiceRequest__c.Patient__c",
  () => ({ default: { fieldApiName: "lfemr__Patient__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Encounter__c",
  () => ({ default: { objectApiName: "lfemr__Encounter__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Encounter__c.Patient__c",
  () => ({ default: { fieldApiName: "lfemr__Patient__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/DiagnosticReport__c.Report_Display__c",
  () => ({ default: { fieldApiName: "lfemr__Report_Display__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/DiagnosticReport__c.Status__c",
  () => ({ default: { fieldApiName: "lfemr__Status__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/DiagnosticReport__c.Report_Code__c",
  () => ({ default: { fieldApiName: "lfemr__Report_Code__c" } }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i += 1) {
    // Flush dependent Apex promises and the rendering they schedule.
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (control) => control.label === label
  );
}
async function mount() {
  const element = createElement("c-emr-diagnostic-report-panel", {
    is: EmrDiagnosticReportPanel
  });
  element.recordId = "patient-current";
  document.body.appendChild(element);
  getReports.emit({ unreviewedReports: [], reviewedReports: [] });
  await flush();
  button(element, "Add").click();
  await flush();
  return element;
}
describe("diagnostic report order linkage", () => {
  beforeEach(() => {
    addLinkedReport.mockResolvedValue({ Id: "report-new" });
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.resetAllMocks();
  });
  it("restricts both order and encounter pickers to the current patient with namespace-aware fields", async () => {
    const element = await mount();
    const pickers = [
      ...element.shadowRoot.querySelectorAll("lightning-record-picker")
    ];
    expect(pickers.map((picker) => picker.objectApiName)).toEqual([
      "lfemr__ServiceRequest__c",
      "lfemr__Encounter__c"
    ]);
    for (const picker of pickers)
      expect(picker.filter.criteria).toEqual([
        {
          fieldPath: "lfemr__Patient__c",
          operator: "eq",
          value: "patient-current"
        }
      ]);
  });
  it("saves the selected service order and encounter then clears them for the next report", async () => {
    const element = await mount();
    const pickers = [
      ...element.shadowRoot.querySelectorAll("lightning-record-picker")
    ];
    pickers[0].dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "order-one" } })
    );
    pickers[1].dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "encounter-one" } })
    );
    element.shadowRoot.querySelector("c-emr-code-search").dispatchEvent(
      new CustomEvent("codeselected", {
        detail: {
          system: "LOINC",
          code: "24323-8",
          display: "Metabolic panel"
        }
      })
    );
    button(element, "Save report").click();
    await flush();
    expect(addLinkedReport).toHaveBeenCalledWith(
      expect.objectContaining({
        patientId: "patient-current",
        serviceRequestId: "order-one",
        encounterId: "encounter-one",
        code: "24323-8",
        status: "Final"
      })
    );
    expect(element.shadowRoot.querySelector("c-emr-modal")).toBeNull();
    button(element, "Add").click();
    await flush();
    for (const picker of element.shadowRoot.querySelectorAll(
      "lightning-record-picker"
    ))
      expect(picker.value).toBeUndefined();
  });
  it("keeps the selected links when the server rejects a mismatched patient order", async () => {
    const element = await mount();
    addLinkedReport.mockRejectedValue({
      body: {
        message: "Select a service order for this patient and encounter."
      }
    });
    const picker = element.shadowRoot.querySelector("lightning-record-picker");
    picker.dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "order-one" } })
    );
    button(element, "Save report").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Select a service order for this patient and encounter."
    );
    expect(element.shadowRoot.querySelector("c-emr-modal")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("lightning-record-picker").value
    ).toBe("order-one");
  });
  it("renders namespaced report status and display values returned by Apex", async () => {
    const element = await mount();
    getReports.emit({
      unreviewedReports: [
        {
          Id: "report-amended",
          lfemr__Report_Display__c: "Corrected metabolic panel",
          lfemr__Status__c: "Amended",
          lfemr__Report_Code__c: "24323-8"
        }
      ],
      reviewedReports: []
    });
    await flush();
    expect(
      [...element.shadowRoot.querySelectorAll("c-emr-record-link")].some(
        (link) => link.label === "Corrected metabolic panel"
      )
    ).toBe(true);
    expect(element.shadowRoot.textContent).toContain("24323-8");
    expect(element.shadowRoot.textContent).toContain("Amended");
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(
      table.columns.find((column) => column.label === "Status").fieldName
    ).toBe("lfemr__Status__c");
    expect(table.data[0].lfemr__Status__c).toBe("Amended");
  });
});
