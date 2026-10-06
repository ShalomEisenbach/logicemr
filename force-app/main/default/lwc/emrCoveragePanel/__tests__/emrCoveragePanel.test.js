import { createElement } from "lwc";
import EmrCoveragePanel from "c/emrCoveragePanel";
import getCoverages from "@salesforce/apex/CoveragePanelController.getCoverages";

jest.mock(
  "@salesforce/apex/CoveragePanelController.getCoverages",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flushPromises = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

describe("c-emr-coverage-panel dates", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("preserves coverage boundary dates in table, card, and edit form", async () => {
    const element = createElement("c-emr-coverage-panel", {
      is: EmrCoveragePanel
    });
    element.recordId = "patient1";
    document.body.appendChild(element);
    getCoverages.emit([
      {
        Id: "coverage1",
        Name: "Annual coverage",
        Status__c: "Active",
        Effective_Start__c: "2026-01-01",
        Effective_End__c: "2026-12-31"
      }
    ]);
    await flushPromises();
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    for (const label of ["Start", "End"]) {
      expect(table.columns.find((column) => column.label === label).type).toBe(
        "date-local"
      );
    }
    expect(table.data[0].Effective_Start__c).toBe("2026-01-01");
    expect(table.data[0].Effective_End__c).toBe("2026-12-31");
    const options = { year: "numeric", month: "short", day: "2-digit" };
    const expectedRange = `${new Date(2026, 0, 1).toLocaleDateString(undefined, options)} – ${new Date(2026, 11, 31).toLocaleDateString(undefined, options)}`;
    expect(element.shadowRoot.querySelector(".stack-detail").textContent).toBe(
      expectedRange
    );

    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "edit" }, row: table.data[0] }
      })
    );
    await Promise.resolve();
    const inputs = [...element.shadowRoot.querySelectorAll("lightning-input")];
    expect(inputs.find((input) => input.name === "effectiveStart").value).toBe(
      "2026-01-01"
    );
    expect(inputs.find((input) => input.name === "effectiveEnd").value).toBe(
      "2026-12-31"
    );
  });
});
