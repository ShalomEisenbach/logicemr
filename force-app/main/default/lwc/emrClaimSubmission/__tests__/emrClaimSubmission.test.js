import { createElement } from "lwc";
import EmrClaimSubmission from "c/emrClaimSubmission";
import getSubmissions from "@salesforce/apex/ClaimSubmissionController.getSubmissions";
import queueSubmission from "@salesforce/apex/ClaimSubmissionController.queueSubmission";
import retrySubmission from "@salesforce/apex/ClaimSubmissionController.retrySubmission";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/ClaimSubmissionController.getSubmissions",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ClaimSubmissionController.queueSubmission",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/ClaimSubmissionController.retrySubmission",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flushPromises = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const findButton = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (button) => button.label === label
  );

const createComponent = () => {
  const element = createElement("c-emr-claim-submission", {
    is: EmrClaimSubmission
  });
  element.superbillId = "a10000000000001";
  element.claimStatus = "Ready";
  document.body.appendChild(element);
  return element;
};

describe("c-emr-claim-submission", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  it("renders submission state and blocks duplicate submission", async () => {
    const element = createComponent();
    getSubmissions.emit([
      {
        Id: "a20000000000001",
        Name: "CLMSUB-00000001",
        Status__c: "Submitted",
        Attempt_Number__c: 1,
        Patient_Control_Number__c: "ABC123",
        Provider_Used__c: "Stedi",
        Correlation_Id__c: "corr-1"
      }
    ]);
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("Submitted");
    expect(element.shadowRoot.textContent).toContain("corr-1");
    expect(findButton(element, "Submit 837P").disabled).toBe(true);
  });

  it("queues a submission after confirmation", async () => {
    jest.spyOn(LightningConfirm, "open").mockResolvedValue(true);
    queueSubmission.mockResolvedValue({ Id: "a20000000000001" });
    const element = createComponent();
    getSubmissions.emit([]);
    await flushPromises();

    findButton(element, "Submit 837P").click();
    await flushPromises();
    await flushPromises();

    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(queueSubmission).toHaveBeenCalledWith({
      superbillId: "a10000000000001"
    });
  });

  it("does not submit when confirmation is canceled", async () => {
    jest.spyOn(LightningConfirm, "open").mockResolvedValue(false);
    const element = createComponent();
    getSubmissions.emit([]);
    await flushPromises();

    findButton(element, "Submit 837P").click();
    await flushPromises();

    expect(queueSubmission).not.toHaveBeenCalled();
  });

  it("retries failed submissions", async () => {
    retrySubmission.mockResolvedValue({ Id: "a20000000000001" });
    const element = createComponent();
    getSubmissions.emit([
      {
        Id: "a20000000000001",
        Name: "CLMSUB-00000001",
        Status__c: "Failed",
        Attempt_Number__c: 1,
        Patient_Control_Number__c: "ABC123",
        Provider_Used__c: "Stedi"
      }
    ]);
    await flushPromises();

    findButton(element, "Retry").click();
    await flushPromises();
    await flushPromises();

    expect(retrySubmission).toHaveBeenCalledWith({
      submissionId: "a20000000000001"
    });
  });

  it("offers recovery for an old queued submission", async () => {
    const element = createComponent();
    getSubmissions.emit([
      {
        Id: "a20000000000001",
        Name: "CLMSUB-00000001",
        Status__c: "Queued",
        Queued_At__c: "2000-01-01T00:00:00.000Z",
        Attempt_Number__c: 0,
        Patient_Control_Number__c: "ABC123",
        Provider_Used__c: "Stedi"
      }
    ]);
    await flushPromises();

    expect(findButton(element, "Recover")).not.toBeUndefined();
  });

  it("renders wire and operation errors", async () => {
    const element = createComponent();
    getSubmissions.error({ message: "Unable to load submissions" });
    await flushPromises();
    expect(element.shadowRoot.textContent).toContain(
      "Unable to load submissions"
    );

    getSubmissions.emit([]);
    queueSubmission.mockRejectedValue({
      body: { message: "Submission failed" }
    });
    jest.spyOn(LightningConfirm, "open").mockResolvedValue(true);
    await flushPromises();
    findButton(element, "Submit 837P").click();
    await flushPromises();
    await flushPromises();
    expect(element.shadowRoot.textContent).toContain("Submission failed");
  });
});
