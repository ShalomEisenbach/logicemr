import { createElement } from "lwc";
import EmrMedicationPanel from "c/emrMedicationPanel";
import getMedications from "@salesforce/apex/MedicationPanelController.getMedications";
import addPrescription from "@salesforce/apex/MedicationPanelController.addPrescription";
import activatePrescription from "@salesforce/apex/MedicationPanelController.activatePrescription";
import renewOrders from "@salesforce/apex/MedicationPanelController.renewOrders";
import discontinueOrders from "@salesforce/apex/MedicationPanelController.discontinueOrders";
import deleteOrders from "@salesforce/apex/MedicationPanelController.deleteOrders";
import deleteReportedMedications from "@salesforce/apex/MedicationPanelController.deleteReportedMedications";
import { getObjectInfo } from "lightning/uiObjectInfoApi";

jest.mock(
  "@salesforce/apex/MedicationPanelController.getMedications",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.addPrescription",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.activatePrescription",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.renewOrders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.discontinueOrders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.deleteOrders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MedicationPanelController.deleteReportedMedications",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const fullPermissions = { createable: true, updateable: true, deletable: true };
const readOnly = { createable: false, updateable: false, deletable: false };
function permissions(request, statement = request) {
  getObjectInfo.emit(request, (config) =>
    config.objectApiName.objectApiName.endsWith("MedicationRequest__c")
  );
  getObjectInfo.emit(statement, (config) =>
    config.objectApiName.objectApiName.endsWith("MedicationStatement__c")
  );
}

function buttons(element, id) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")]
    .filter((button) => !id || button.dataset.id === id)
    .map((button) => button.label);
}

function rowActions(table, row) {
  const done = jest.fn();
  table.columns
    .find((column) => column.type === "action")
    .typeAttributes.rowActions(row, done);
  return done.mock.calls[0][0].map((action) => action.name);
}
const flush = async () => {
  for (let i = 0; i < 12; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

describe("prescription capture", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("sends dispensing details as numeric values with the prescription", async () => {
    addPrescription.mockResolvedValue({ Id: "rx1" });
    const element = createElement("c-emr-medication-panel", {
      is: EmrMedicationPanel
    });
    element.recordId = "patient1";
    document.body.appendChild(element);
    permissions(fullPermissions);
    getMedications.emit({ activeOrders: [], reportedMedications: [] });
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.label === "Add")
      .click();
    await flush();
    for (const [name, value] of [
      ["dispenseQuantity", "30"],
      ["refills", "2"],
      ["pharmacy", "Local pharmacy"]
    ]) {
      const control = [
        ...element.shadowRoot.querySelectorAll("lightning-input")
      ].find((item) => item.name === name);
      control.value = value;
      control.dispatchEvent(new CustomEvent("change"));
    }
    for (const control of element.shadowRoot.querySelectorAll(
      "lightning-input, lightning-combobox"
    )) {
      control.reportValidity = jest.fn(() => true);
    }
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.label === "Save medication")
      .click();
    await flush();
    expect(addPrescription).toHaveBeenCalledWith({
      input: expect.objectContaining({
        patientId: "patient1",
        dispenseQuantity: 30,
        refills: 2,
        pharmacy: "Local pharmacy"
      })
    });
  });

  it("offers activation for a draft and sends its ID", async () => {
    activatePrescription.mockResolvedValue();
    const element = createElement("c-emr-medication-panel", {
      is: EmrMedicationPanel
    });
    element.recordId = "patient1";
    document.body.appendChild(element);
    permissions(fullPermissions);
    getMedications.emit({
      activeOrders: [
        {
          Id: "draft1",
          Medication_Display__c: "Draft medication",
          Status__c: "Draft",
          Intent__c: "Order"
        }
      ],
      reportedMedications: []
    });
    await flush();
    const button = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((item) => item.label === "Activate");
    expect(button).toBeDefined();
    button.click();
    await flush();
    expect(activatePrescription).toHaveBeenCalledWith({ requestId: "draft1" });
  });

  it("keeps readable medication and printable orders while hiding mutations from read-only users", async () => {
    const element = createElement("c-emr-medication-panel", {
      is: EmrMedicationPanel
    });
    document.body.appendChild(element);
    permissions(readOnly);
    const active = {
      Id: "active1",
      Medication_Display__c: "Readable prescription",
      Status__c: "Active",
      Intent__c: "Order"
    };
    const draft = { Id: "draft1", Status__c: "Draft", Intent__c: "Order" };
    getMedications.emit({
      activeOrders: [active, draft],
      reportedMedications: [
        { Id: "reported1", Medication_Display__c: "Reported medicine" }
      ]
    });
    await flush();
    expect(buttons(element)).toEqual(["Print"]);
    const labels = [
      ...element.shadowRoot.querySelectorAll("c-emr-record-link")
    ].map((link) => link.label);
    expect(labels).toContain("Readable prescription");
    expect(labels).toContain("Reported medicine");
    const tables = element.shadowRoot.querySelectorAll("lightning-datatable");
    expect(rowActions(tables[0], active)).toEqual(["print"]);
    expect(rowActions(tables[0], draft)).toEqual([]);
    expect(tables[1].columns.some((column) => column.type === "action")).toBe(
      false
    );
    for (const name of [
      "renew",
      "discontinue",
      "delete",
      "activate",
      "editDraft"
    ]) {
      tables[0].dispatchEvent(
        new CustomEvent("rowaction", {
          detail: { action: { name }, row: active }
        })
      );
    }
    tables[1].dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "deleteReported" }, row: { Id: "reported1" } }
      })
    );
    await flush();
    expect(renewOrders).not.toHaveBeenCalled();
    expect(discontinueOrders).not.toHaveBeenCalled();
    expect(deleteOrders).not.toHaveBeenCalled();
    expect(activatePrescription).not.toHaveBeenCalled();
    expect(deleteReportedMedications).not.toHaveBeenCalled();
  });

  it("uses independent request and reported-medication permissions", async () => {
    const element = createElement("c-emr-medication-panel", {
      is: EmrMedicationPanel
    });
    document.body.appendChild(element);
    permissions(
      { createable: true, updateable: false, deletable: true },
      readOnly
    );
    getMedications.emit({
      activeOrders: [{ Id: "draft1", Status__c: "Draft", Intent__c: "Order" }],
      reportedMedications: [{ Id: "reported1" }]
    });
    await flush();
    expect(buttons(element)).toContain("Add");
    expect(buttons(element, "draft1")).toEqual(["Delete"]);
    expect(buttons(element, "reported1")).toEqual([]);

    permissions(
      { createable: false, updateable: true, deletable: false },
      { ...readOnly, deletable: true }
    );
    await flush();
    expect(buttons(element)).not.toContain("Add");
    expect(buttons(element, "draft1")).toEqual(["Edit", "Activate"]);
    expect(buttons(element, "reported1")).toEqual(["Delete"]);
  });

  it("prints and selects only Active Orders and activates only Draft Orders", async () => {
    const element = createElement("c-emr-medication-panel", {
      is: EmrMedicationPanel
    });
    document.body.appendChild(element);
    permissions(fullPermissions);
    const orders = [
      { Id: "activeOrder", Status__c: "Active", Intent__c: "Order" },
      { Id: "draftOrder", Status__c: "Draft", Intent__c: "Order" },
      { Id: "draftPlan", Status__c: "Draft", Intent__c: "Plan" },
      { Id: "activePlan", Status__c: "Active", Intent__c: "Plan" },
      { Id: "activeProposal", Status__c: "Active", Intent__c: "Proposal" },
      { Id: "heldOrder", Status__c: "On Hold", Intent__c: "Order" }
    ];
    getMedications.emit({ activeOrders: orders, reportedMedications: [] });
    await flush();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(rowActions(table, orders[0])).toEqual([
      "print",
      "renew",
      "discontinue",
      "delete"
    ]);
    expect(rowActions(table, orders[1])).toEqual([
      "editDraft",
      "activate",
      "delete"
    ]);
    expect(rowActions(table, orders[2])).toEqual(["editDraft", "delete"]);
    for (const row of orders.slice(3)) {
      expect(rowActions(table, row)).toEqual(["discontinue", "delete"]);
      expect(buttons(element, row.Id)).not.toContain("Print");
    }
    table.dispatchEvent(
      new CustomEvent("rowselection", { detail: { selectedRows: orders } })
    );
    await flush();
    expect(table.selectedRows).toEqual(["activeOrder"]);
    expect(
      element.shadowRoot.querySelector(".share-slot c-emr-document-share")
        .recordIds
    ).toEqual(["activeOrder"]);
    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "activate" }, row: orders[2] }
      })
    );
    await flush();
    expect(activatePrescription).not.toHaveBeenCalled();
    const print = jest
      .spyOn(element.shadowRoot.querySelector(".hidden-share"), "print")
      .mockResolvedValue();
    for (const row of orders.slice(1)) {
      table.dispatchEvent(
        new CustomEvent("rowaction", {
          detail: { action: { name: "print" }, row }
        })
      );
    }
    await flush();
    expect(print).not.toHaveBeenCalled();
    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "print" }, row: orders[0] }
      })
    );
    await flush();
    expect(print).toHaveBeenCalledWith(["activeOrder"]);
  });
});
