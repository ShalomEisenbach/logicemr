import { createElement } from "lwc";
import EmrEncounterWorkspace from "c/emrEncounterWorkspace";
import { getRecord } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import getChecklist from "@salesforce/apex/EncounterCompletionService.getChecklist";
import retryHandoff from "@salesforce/apex/EncounterCompletionService.retryHandoff";
import transitionStatus from "@salesforce/apex/EncounterWorkspaceController.transitionStatus";
import getDiagnoses from "@salesforce/apex/EncounterWorkspaceController.getDiagnoses";

jest.mock(
  "@salesforce/apex/EncounterCompletionService.getChecklist",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EncounterCompletionService.retryHandoff",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EncounterWorkspaceController.transitionStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EncounterWorkspaceController.getDiagnoses",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EncounterWorkspaceController.addDiagnosis",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EncounterWorkspaceController.deleteDiagnoses",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VitalsCaptureController.getEncounterVitalDetails",
  () => ({ default: jest.fn().mockResolvedValue({}) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NoteEditorController.getNotes",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn().mockResolvedValue() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i += 1) {
    // Flush dependent Apex promises and the rendering they schedule.
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
const checklist = {
  items: [
    { label: "Allergies reviewed", complete: false },
    { label: "Clinical note signed", complete: true }
  ],
  handoffStatus: "Failed",
  handoffError:
    "Billing handoff failed. Review billing configuration and retry.",
  canRetry: true
};
function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (control) => control.label === label
  );
}
async function mount(status = "Finished") {
  const element = createElement("c-emr-encounter-workspace", {
    is: EmrEncounterWorkspace
  });
  element.recordId = "encounter-one";
  document.body.appendChild(element);
  await flush();
  getRecord.emit({
    apiName: "Encounter__c",
    id: "encounter-one",
    fields: {
      Status__c: { value: status },
      Patient__c: { value: "patient-one" }
    }
  });
  getDiagnoses.emit([]);
  getChecklist.emit(checklist);
  await flush();
  return element;
}
describe("encounter completion checklist and handoff", () => {
  beforeEach(() => {
    retryHandoff.mockResolvedValue();
    transitionStatus.mockResolvedValue({});
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });
  it("shows clinical reconciliation gaps and an actionable failed handoff", async () => {
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain(
      "Allergies reviewed: Needs attention"
    );
    expect(element.shadowRoot.textContent).toContain(
      "Clinical note signed: Complete"
    );
    expect(element.shadowRoot.textContent).toContain(checklist.handoffError);
    expect(button(element, "Retry completion handoff")).toBeDefined();
    expect(button(element, "Mark Finished")).toBeUndefined();
  });
  it("retries handoff once and refreshes checklist after success", async () => {
    const element = await mount();
    button(element, "Retry completion handoff").click();
    await flush();
    expect(retryHandoff).toHaveBeenCalledWith({ encounterId: "encounter-one" });
    expect(refreshApex).toHaveBeenCalled();
    getChecklist.emit({
      ...checklist,
      handoffStatus: "Completed",
      handoffError: null,
      canRetry: false
    });
    await flush();
    expect(button(element, "Retry completion handoff")).toBeUndefined();
    expect(element.shadowRoot.textContent).toContain(
      "Appointment and billing handoff: Completed"
    );
  });
  it("keeps a retry failure visible with the visit completed", async () => {
    const element = await mount();
    retryHandoff.mockRejectedValue({
      body: { message: "Completion handoff is already pending." }
    });
    button(element, "Retry completion handoff").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Completion handoff is already pending."
    );
    expect(button(element, "Mark Finished")).toBeUndefined();
  });
  it("allows ending an in-progress visit with visible chart gaps and refreshes the checklist", async () => {
    const element = await mount("In Progress");
    button(element, "Mark Finished").click();
    await flush();
    expect(transitionStatus).toHaveBeenCalledWith({
      encounterId: "encounter-one",
      newStatus: "Finished"
    });
    expect(refreshApex).toHaveBeenCalled();
  });
});
