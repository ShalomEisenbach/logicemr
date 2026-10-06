import { createElement } from "lwc";
import EmrAllergyPanel from "c/emrAllergyPanel";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import getAllergies from "@salesforce/apex/AllergyPanelController.getAllergies";
import getReviewState from "@salesforce/apex/AllergyPanelController.getReviewState";
import reviewAllergies from "@salesforce/apex/AllergyPanelController.reviewAllergies";
import inactivateAllergies from "@salesforce/apex/AllergyPanelController.inactivateAllergies";
import deleteAllergies from "@salesforce/apex/AllergyPanelController.deleteAllergies";

jest.mock(
  "@salesforce/schema/Patient__c",
  () => ({ default: { objectApiName: "lfemr__Patient__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/AllergyIntolerance__c",
  () => ({ default: { objectApiName: "lfemr__AllergyIntolerance__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Patient__c.Allergy_Review_Status__c",
  () => ({ default: { fieldApiName: "lfemr__Allergy_Review_Status__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/AllergyIntolerance__c.Clinical_Status__c",
  () => ({ default: { fieldApiName: "lfemr__Clinical_Status__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/AllergyIntolerance__c.Allergen_Display__c",
  () => ({ default: { fieldApiName: "lfemr__Allergen_Display__c" } }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AllergyPanelController.getAllergies",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AllergyPanelController.getReviewState",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AllergyPanelController.reviewAllergies",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AllergyPanelController.inactivateAllergies",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AllergyPanelController.deleteAllergies",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const activeAllergy = {
  Id: "allergy1",
  lfemr__Clinical_Status__c: "Active",
  lfemr__Allergen_Display__c: "Penicillin"
};
function permissions(options = {}) {
  const {
    patientEdit = true,
    reviewEdit = true,
    create = true,
    edit = true,
    statusEdit = true,
    remove = false
  } = options;
  const forObject = (objectApiName) => (config) =>
    (config.objectApiName?.objectApiName || config.objectApiName) ===
    objectApiName;
  getObjectInfo.emit(
    {
      apiName: "lfemr__Patient__c",
      updateable: patientEdit,
      fields: { lfemr__Allergy_Review_Status__c: { updateable: reviewEdit } }
    },
    forObject("lfemr__Patient__c")
  );
  getObjectInfo.emit(
    {
      apiName: "lfemr__AllergyIntolerance__c",
      createable: create,
      updateable: edit,
      deletable: remove,
      fields: { lfemr__Clinical_Status__c: { updateable: statusEdit } }
    },
    forObject("lfemr__AllergyIntolerance__c")
  );
}
function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (control) => control.label === label
  );
}
const flush = async () => {
  for (let i = 0; i < 6; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
async function mount(rows = [activeAllergy]) {
  const element = createElement("c-emr-allergy-panel", { is: EmrAllergyPanel });
  element.recordId = "patient1";
  document.body.appendChild(element);
  await flush();
  getAllergies.emit(rows);
  getReviewState.emit({ status: "Unknown" });
  await flush();
  return element;
}

describe("allergy reconciliation", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("shows Unknown until an empty chart is explicitly confirmed", async () => {
    reviewAllergies.mockResolvedValue();
    const element = createElement("c-emr-allergy-panel", {
      is: EmrAllergyPanel
    });
    element.recordId = "patient1";
    document.body.appendChild(element);
    await flush();
    permissions();
    getAllergies.emit([]);
    getReviewState.emit({ status: "Unknown" });
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toBe("Unknown");
    button(element, "Confirm no known allergies").click();
    await flush();
    expect(reviewAllergies).toHaveBeenCalledWith({
      patientId: "patient1",
      noKnownAllergies: true
    });
  });

  it("confirms active allergy review separately from no known allergies", async () => {
    reviewAllergies.mockResolvedValue();
    const element = createElement("c-emr-allergy-panel", {
      is: EmrAllergyPanel
    });
    element.recordId = "patient1";
    document.body.appendChild(element);
    await flush();
    permissions();
    getAllergies.emit([activeAllergy]);
    await flush();
    button(element, "Confirm allergies reviewed").click();
    await flush();
    expect(reviewAllergies).toHaveBeenCalledWith({
      patientId: "patient1",
      noKnownAllergies: false
    });
  });

  it("keeps clinical actions hidden while object permissions are loading", async () => {
    const element = await mount();
    expect(button(element, "Add")).toBeUndefined();
    expect(button(element, "Confirm allergies reviewed")).toBeUndefined();
    expect(button(element, "Inactivate")).toBeUndefined();
    expect(button(element, "Delete")).toBeUndefined();
    expect(
      element.shadowRoot
        .querySelector("lightning-datatable")
        .columns.some((column) => column.type === "action")
    ).toBe(false);
  });

  it("shows a read-only allergy view for billing permissions and ignores forged mutation events", async () => {
    const element = await mount();
    permissions({
      patientEdit: true,
      reviewEdit: false,
      create: false,
      edit: false,
      statusEdit: false,
      remove: false
    });
    await flush();
    expect(
      [...element.shadowRoot.querySelectorAll("c-emr-record-link")].some(
        (link) => link.label === "Penicillin"
      )
    ).toBe(true);
    expect(button(element, "Add")).toBeUndefined();
    expect(button(element, "Confirm allergies reviewed")).toBeUndefined();
    expect(button(element, "Inactivate")).toBeUndefined();
    expect(button(element, "Delete")).toBeUndefined();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    for (const action of ["inactivate", "delete"])
      table.dispatchEvent(
        new CustomEvent("rowaction", {
          detail: { action: { name: action }, row: { Id: "allergy1" } }
        })
      );
    await flush();
    expect(inactivateAllergies).not.toHaveBeenCalled();
    expect(deleteAllergies).not.toHaveBeenCalled();
  });

  it("requires field edit access in addition to patient and allergy object edit access", async () => {
    const element = await mount();
    permissions({
      patientEdit: true,
      reviewEdit: false,
      create: true,
      edit: true,
      statusEdit: false
    });
    await flush();
    expect(button(element, "Add")).toBeDefined();
    expect(button(element, "Confirm allergies reviewed")).toBeUndefined();
    expect(button(element, "Inactivate")).toBeUndefined();
    expect(
      element.shadowRoot
        .querySelector("lightning-datatable")
        .columns.some((column) => column.type === "action")
    ).toBe(false);
  });

  it("offers inactivation to clinicians without offering record deletion", async () => {
    const element = await mount();
    permissions();
    await flush();
    expect(button(element, "Inactivate")).toBeDefined();
    expect(button(element, "Delete")).toBeUndefined();
    const actions = jest.fn();
    element.shadowRoot
      .querySelector("lightning-datatable")
      .columns.find((column) => column.type === "action")
      .typeAttributes.rowActions(activeAllergy, actions);
    expect(actions).toHaveBeenCalledWith([
      { label: "Inactivate", name: "inactivate" }
    ]);
  });

  it("offers deletion independently only when object delete access is granted", async () => {
    const element = await mount();
    permissions({
      create: false,
      edit: false,
      statusEdit: false,
      remove: true,
      patientEdit: false
    });
    await flush();
    expect(button(element, "Inactivate")).toBeUndefined();
    expect(button(element, "Delete")).toBeDefined();
    const actions = jest.fn();
    element.shadowRoot
      .querySelector("lightning-datatable")
      .columns.find((column) => column.type === "action")
      .typeAttributes.rowActions(activeAllergy, actions);
    expect(actions).toHaveBeenCalledWith([{ label: "Delete", name: "delete" }]);
  });
});
