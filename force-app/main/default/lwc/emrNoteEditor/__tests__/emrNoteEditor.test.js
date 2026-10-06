import { createElement } from "lwc";
import EmrNoteEditor from "c/emrNoteEditor";
import getActiveTemplates from "@salesforce/apex/NoteEditorController.getActiveTemplates";
import getNotes from "@salesforce/apex/NoteEditorController.getNotes";
import createAddendum from "@salesforce/apex/NoteEditorController.createAddendum";
import saveDraft from "@salesforce/apex/NoteEditorController.saveDraft";
import signNote from "@salesforce/apex/NoteEditorController.signNote";

jest.mock(
  "@salesforce/apex/NoteEditorController.getActiveTemplates",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NoteEditorController.getNotes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NoteEditorController.createAddendum",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NoteEditorController.saveDraft",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NoteEditorController.signNote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const original = {
  noteId: "original",
  noteType: "Consult",
  body: "<p>Original assessment</p>",
  status: "Signed",
  signedDate: "2026-10-06T15:00:00Z",
  signedByName: "Dr. Clinician"
};
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
async function mount(recordId = "encounter-current") {
  const element = createElement("c-emr-note-editor", { is: EmrNoteEditor });
  element.recordId = recordId;
  document.body.appendChild(element);
  getActiveTemplates.emit([]);
  await flush();
  return element;
}
describe("signed clinical note addenda", () => {
  beforeEach(() => {
    getNotes.mockResolvedValue([original]);
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.resetAllMocks();
  });
  it("shows signer provenance and read-only signed content with an addendum action", async () => {
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("Dr. Clinician");
    expect(element.shadowRoot.textContent).toContain("Original assessment");
    expect(element.shadowRoot.querySelector("lightning-textarea")).toBeNull();
    expect(button(element, "Sign")).toBeUndefined();
    expect(button(element, "Add addendum")).toBeDefined();
  });
  it("creates a linked signed addendum without editing the original note", async () => {
    const element = await mount();
    const addendum = {
      noteId: "addendum",
      addendumToId: "original",
      noteType: "Consult",
      body: "Additional information",
      status: "Signed",
      signedDate: original.signedDate,
      signedByName: "Dr. Clinician"
    };
    createAddendum.mockResolvedValue(addendum);
    getNotes.mockResolvedValue([addendum, original]);
    button(element, "Add addendum").click();
    await flush();
    expect(element.shadowRoot.querySelector("c-emr-modal").title).toBe(
      "Clinical note addendum"
    );
    const editor = element.shadowRoot.querySelector("lightning-textarea");
    editor.value = "Additional information";
    editor.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Additional information" } })
    );
    button(element, "Sign").click();
    await flush();
    expect(createAddendum).toHaveBeenCalledWith({
      signedNoteId: "original",
      body: "Additional information",
      sign: true
    });
    expect(signNote).not.toHaveBeenCalled();
    expect(saveDraft).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain("Original assessment");
    expect(
      [...element.shadowRoot.querySelectorAll("c-emr-record-link")].some(
        (link) =>
          link.recordId === "original" && link.label === "original signed note"
      )
    ).toBe(true);
    expect(element.shadowRoot.querySelector("c-emr-modal")).toBeNull();
  });
  it("keeps the addendum form and original content visible after a save failure", async () => {
    const element = await mount();
    createAddendum.mockRejectedValue({
      body: { message: "Enter clinical note content before signing." }
    });
    button(element, "Add addendum").click();
    await flush();
    button(element, "Sign").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Enter clinical note content before signing."
    );
    expect(element.shadowRoot.textContent).toContain("Original assessment");
    expect(element.shadowRoot.querySelector("c-emr-modal")).not.toBeNull();
  });
  it("ignores late note responses after switching encounters", async () => {
    let resolveOld;
    getNotes.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    const element = await mount("encounter-old");
    getNotes.mockResolvedValueOnce([
      {
        ...original,
        noteId: "current-note",
        body: "Current patient assessment"
      }
    ]);
    element.recordId = "encounter-current";
    await flush();
    resolveOld([{ ...original, body: "Previous patient assessment" }]);
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Current patient assessment"
    );
    expect(element.shadowRoot.textContent).not.toContain(
      "Previous patient assessment"
    );
  });
});
