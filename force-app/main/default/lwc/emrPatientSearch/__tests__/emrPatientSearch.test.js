import { createElement } from "lwc";
import EmrPatientSearch from "c/emrPatientSearch";
import searchPatients from "@salesforce/apex/PatientSearchController.search";

jest.mock(
  "@salesforce/apex/PatientSearchController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

describe("c-emr-patient-search dates", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it("uses the same stored birthday in the search table and patient card", async () => {
    jest.useFakeTimers();
    searchPatients.mockResolvedValue([
      { Id: "patient1", First_Name__c: "Maya", Date_of_Birth__c: "1988-03-14" }
    ]);
    const element = createElement("c-emr-patient-search", {
      is: EmrPatientSearch
    });
    document.body.appendChild(element);
    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Maya";
    input.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(300);
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].Date_of_Birth__c).toBe("1988-03-14");
    expect(table.columns.find((column) => column.label === "DOB").type).toBe(
      "date-local"
    );
    expect(
      element.shadowRoot.querySelector(".stack-meta").textContent
    ).toContain(new Date(1988, 2, 14).toLocaleDateString());
  });
});
