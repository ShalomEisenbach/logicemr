import { createElement } from "lwc";
import EmrPayerSearch from "c/emrPayerSearch";
import getPayer from "@salesforce/apex/PayerSearchController.getPayer";

jest.mock(
  "@salesforce/apex/PayerSearchController.searchPayers",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PayerSearchController.getPayer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PayerSearchController.savePayerIdentifier",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () => Promise.resolve();

describe("c-emr-payer-search", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the namespace-safe payer identifier returned by Apex", async () => {
    getPayer.mockResolvedValue({
      payerId: "a01000000000001AAA",
      name: "Health Plan",
      payerIdentifier: "HPQRS"
    });
    const element = createElement("c-emr-payer-search", { is: EmrPayerSearch });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);

    await flushPromises();
    await flushPromises();

    expect(getPayer).toHaveBeenCalledWith({ payerId: "a01000000000001AAA" });
    expect(element.shadowRoot.textContent).toContain(
      "Current Stedi payer id: HPQRS"
    );
  });
});
