import { createElement } from "lwc";
import EmrProcedurePanel from "c/emrProcedurePanel";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import LightningConfirm from "lightning/confirm";
import getProcedures from "@salesforce/apex/ProcedurePanelController.getProcedures";
import addLinkedProcedure from "@salesforce/apex/ProcedurePanelController.addLinkedProcedure";
import completeProcedures from "@salesforce/apex/ProcedurePanelController.completeProcedures";
import deleteProcedures from "@salesforce/apex/ProcedurePanelController.deleteProcedures";

jest.mock(
  "@salesforce/apex/ProcedurePanelController.getProcedures",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ProcedurePanelController.addLinkedProcedure",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ProcedurePanelController.completeProcedures",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ProcedurePanelController.deleteProcedures",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn().mockResolvedValue() }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/schema/Procedure__c",
  () => ({ default: { objectApiName: "lfemr__Procedure__c" } }),
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
  "@salesforce/schema/Procedure__c.Encounter__c",
  () => ({ default: { fieldApiName: "lfemr__Encounter__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Procedure__c.Procedure_Display__c",
  () => ({ default: { fieldApiName: "lfemr__Procedure_Display__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Procedure__c.Procedure_Code__c",
  () => ({ default: { fieldApiName: "lfemr__Procedure_Code__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Procedure__c.Status__c",
  () => ({ default: { fieldApiName: "lfemr__Status__c" } }),
  { virtual: true }
);

const pendingProcedure = {
  Id: "procedure1",
  lfemr__Procedure_Display__c: "Office visit",
  lfemr__Procedure_Code__c: "99213",
  lfemr__Status__c: "In Progress",
  lfemr__Encounter__c: "encounter1",
  lfemr__Encounter__r: { Name: "Today's outpatient visit" }
};
const flush = async () => {
  for (let i = 0; i < 10; i += 1) {
    // Flush navigation promises and the rendering they schedule.
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
function permissions(options = {}) {
  const {
    create = true,
    edit = true,
    statusEdit = true,
    linkCreate = true,
    remove = false
  } = options;
  getObjectInfo.emit({
    apiName: "lfemr__Procedure__c",
    createable: create,
    updateable: edit,
    deletable: remove,
    fields: {
      lfemr__Status__c: { updateable: statusEdit },
      lfemr__Encounter__c: { createable: linkCreate }
    }
  });
}
function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (control) => control.label === label
  );
}
async function mount(options = {}) {
  const element = createElement("c-emr-procedure-panel", {
    is: EmrProcedurePanel
  });
  element.recordId = "patient-current";
  document.body.appendChild(element);
  await flush();
  if (options.permissions !== false) permissions(options);
  getProcedures.emit([pendingProcedure]);
  await flush();
  return element;
}
async function openForm(element) {
  button(element, "Add").click();
  await flush();
}
function selectEncounter(element, recordId = "encounter-selected") {
  element.shadowRoot
    .querySelector("lightning-record-picker")
    .dispatchEvent(new CustomEvent("change", { detail: { recordId } }));
}
function rowAction(element, name) {
  element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
    new CustomEvent("rowaction", {
      detail: { action: { name }, row: pendingProcedure }
    })
  );
}

describe("procedure encounter linkage and role permissions", () => {
  beforeEach(() => {
    addLinkedProcedure.mockResolvedValue({ Id: "procedure-new" });
    completeProcedures.mockResolvedValue();
    deleteProcedures.mockResolvedValue();
    LightningConfirm.open.mockResolvedValue(true);
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("filters the optional encounter picker to this patient with namespaced schema fields", async () => {
    const element = await mount();
    await openForm(element);
    const picker = element.shadowRoot.querySelector("lightning-record-picker");
    expect(picker.objectApiName).toBe("lfemr__Encounter__c");
    expect(picker.required).toBeFalsy();
    expect(picker.filter.criteria).toEqual([
      {
        fieldPath: "lfemr__Patient__c",
        operator: "eq",
        value: "patient-current"
      }
    ]);
  });

  it("sends the selected encounter in one creation call and resets it after success", async () => {
    const element = await mount();
    await openForm(element);
    selectEncounter(element);
    element.shadowRoot.querySelector("c-emr-code-search").dispatchEvent(
      new CustomEvent("codeselected", {
        detail: {
          system: "CPT",
          code: "99213",
          display: "Office visit",
          recordId: "code1"
        }
      })
    );
    button(element, "Save procedure").click();
    await flush();
    expect(addLinkedProcedure).toHaveBeenCalledTimes(1);
    expect(addLinkedProcedure).toHaveBeenCalledWith(
      expect.objectContaining({
        patientId: "patient-current",
        encounterId: "encounter-selected",
        code: "99213",
        codeReferenceId: "code1",
        status: "Completed"
      })
    );
    expect(element.shadowRoot.querySelector("c-emr-modal")).toBeNull();
    await openForm(element);
    expect(
      element.shadowRoot.querySelector("lightning-record-picker").value
    ).toBeUndefined();
  });

  it("allows patient-level historical procedures and resets a cancelled link", async () => {
    const element = await mount();
    await openForm(element);
    selectEncounter(element);
    button(element, "Cancel").click();
    await flush();
    await openForm(element);
    expect(
      element.shadowRoot.querySelector("lightning-record-picker").value
    ).toBeUndefined();
    button(element, "Save procedure").click();
    await flush();
    expect(addLinkedProcedure).toHaveBeenCalledWith(
      expect.objectContaining({ encounterId: null })
    );
  });

  it("retains the selected visit and reports the server validation error without retrying", async () => {
    const element = await mount();
    await openForm(element);
    selectEncounter(element);
    addLinkedProcedure.mockRejectedValueOnce({
      body: { message: "Select an encounter for this patient." }
    });
    button(element, "Save procedure").click();
    await flush();
    expect(addLinkedProcedure).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.textContent).toContain(
      "Select an encounter for this patient."
    );
    expect(
      element.shadowRoot.querySelector("lightning-record-picker").value
    ).toBe("encounter-selected");
    expect(element.shadowRoot.querySelector("c-emr-modal")).not.toBeNull();
  });

  it("renders namespace-qualified encounter links and procedure status", async () => {
    const element = await mount();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].encounterLabel).toBe("Today's outpatient visit");
    expect(
      table.columns.find((column) => column.label === "Status").fieldName
    ).toBe("lfemr__Status__c");
    expect(
      [...element.shadowRoot.querySelectorAll("c-emr-record-link")].some(
        (link) =>
          link.recordId === "encounter1" &&
          link.objectApiName === "lfemr__Encounter__c" &&
          link.label === "Today's outpatient visit"
      )
    ).toBe(true);
  });

  it("keeps mutation controls hidden while permissions load and ignores forged billing actions", async () => {
    const element = await mount({ permissions: false });
    expect(button(element, "Add")).toBeUndefined();
    expect(button(element, "Complete")).toBeUndefined();
    expect(button(element, "Delete")).toBeUndefined();
    permissions({ create: false, edit: false, statusEdit: false });
    await flush();
    expect(
      element.shadowRoot
        .querySelector("lightning-datatable")
        .columns.some((column) => column.type === "action")
    ).toBe(false);
    rowAction(element, "complete");
    rowAction(element, "delete");
    await flush();
    expect(completeProcedures).not.toHaveBeenCalled();
    expect(deleteProcedures).not.toHaveBeenCalled();
    expect(LightningConfirm.open).not.toHaveBeenCalled();
  });

  it("allows clinician completion but preserves the existing restriction on deletion", async () => {
    const element = await mount();
    expect(button(element, "Add")).toBeDefined();
    expect(button(element, "Complete")).toBeDefined();
    expect(button(element, "Delete")).toBeUndefined();
    const actions = jest.fn();
    element.shadowRoot
      .querySelector("lightning-datatable")
      .columns.find((column) => column.type === "action")
      .typeAttributes.rowActions(pendingProcedure, actions);
    expect(actions).toHaveBeenCalledWith([
      { label: "Complete", name: "complete" }
    ]);
    rowAction(element, "delete");
    rowAction(element, "complete");
    await flush();
    expect(deleteProcedures).not.toHaveBeenCalled();
    expect(completeProcedures).toHaveBeenCalledWith({
      procedureIds: ["procedure1"]
    });
  });

  it("requires Status field edit access and independently honors delete permission", async () => {
    const element = await mount({ statusEdit: false, remove: true });
    expect(button(element, "Complete")).toBeUndefined();
    expect(button(element, "Delete")).toBeDefined();
    rowAction(element, "complete");
    rowAction(element, "delete");
    await flush();
    expect(completeProcedures).not.toHaveBeenCalled();
    expect(deleteProcedures).toHaveBeenCalledWith({
      procedureIds: ["procedure1"]
    });
  });

  it("does not submit a selected encounter without lookup field creation permission", async () => {
    const element = await mount();
    await openForm(element);
    selectEncounter(element);
    permissions({ linkCreate: false });
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-record-picker")
    ).toBeNull();
    button(element, "Save procedure").click();
    await flush();
    expect(addLinkedProcedure).toHaveBeenCalledWith(
      expect.objectContaining({ encounterId: null })
    );
  });

  it("blocks a stale form save when create permission becomes unavailable", async () => {
    const element = await mount();
    await openForm(element);
    permissions({ create: false });
    await flush();
    const save = button(element, "Save procedure");
    expect(save.disabled).toBe(true);
    save.dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(addLinkedProcedure).not.toHaveBeenCalled();
  });
});
