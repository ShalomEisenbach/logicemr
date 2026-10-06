import { createElement } from "lwc";
import EmrEligibilityQueue from "c/emrEligibilityQueue";
import getWorkQueue from "@salesforce/apex/EligibilityCheckController.getWorkQueue";
import retryCheck from "@salesforce/apex/EligibilityCheckController.retryCheck";

jest.mock(
  "@salesforce/apex/EligibilityCheckController.getWorkQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EligibilityCheckController.retryCheck",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/LogicEMR_Run_Eligibility",
  () => ({ default: true }),
  { virtual: true }
);

const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};
const errorRow = {
  id: "check-error",
  name: "EC-1",
  status: "Error",
  mode: "test",
  traceId: "trace-1",
  error: "AAA 72: Invalid member",
  canRetry: true
};
const successRow = {
  id: "check-success",
  name: "EC-2",
  status: "Inactive",
  mode: "production",
  canRetry: false
};

async function mount() {
  const element = createElement("c-emr-eligibility-queue", {
    is: EmrEligibilityQueue
  });
  document.body.appendChild(element);
  await flush();
  element.shadowRoot.querySelectorAll("[data-field]").forEach((input) => {
    input.reportValidity = jest.fn(() => true);
  });
  return element;
}
function button(element, label) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (item) => item.label === label
  );
}
function change(element, field, value) {
  const input = element.shadowRoot.querySelector(`[data-field="${field}"]`);
  input.value = value;
  input.dispatchEvent(
    new CustomEvent("change", { detail: field === "outcome" ? { value } : {} })
  );
}
function action(element, row, name = "retry") {
  element.shadowRoot
    .querySelector("lightning-datatable")
    .dispatchEvent(
      new CustomEvent("rowaction", { detail: { action: { name }, row } })
    );
}

describe("eligibility operations queue", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    getWorkQueue.mockResolvedValue({
      rows: [errorRow, successRow],
      hasMore: false
    });
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllTimers();
    jest.useRealTimers();
    jest.resetAllMocks();
  });

  it("shows modes, traces, success counts and grouped rejection reasons", async () => {
    getWorkQueue.mockResolvedValue({
      rows: [errorRow, { ...errorRow, id: "second" }, successRow],
      hasMore: true
    });
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain(
      "3 checks shown · 1 successful · 2 errors"
    );
    expect(element.shadowRoot.textContent).toContain(
      "AAA 72: Invalid member — 2"
    );
    expect(element.shadowRoot.textContent).toContain("newest 100");
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0]).toMatchObject({
      mode: "test",
      traceId: "trace-1",
      retryDisabled: false
    });
    expect(table.data[2].retryDisabled).toBe(true);
  });

  it("applies all filters on demand and polls with the applied filters", async () => {
    const element = await mount();
    change(element, "outcome", "Error");
    change(element, "payer", "Aetna");
    change(element, "patient", "Doe");
    change(element, "startDate", "2026-09-01");
    change(element, "endDate", "2026-09-16");
    expect(getWorkQueue).toHaveBeenCalledTimes(1);
    button(element, "Apply filters").click();
    await flush();
    const expected = {
      outcome: "Error",
      payer: "Aetna",
      patient: "Doe",
      startDate: "2026-09-01",
      endDate: "2026-09-16"
    };
    expect(getWorkQueue).toHaveBeenLastCalledWith(expected);
    change(element, "payer", "Unsaved edit");
    jest.advanceTimersByTime(30000);
    await flush();
    expect(getWorkQueue).toHaveBeenLastCalledWith(expected);
  });

  it("rejects reversed dates without querying", async () => {
    const element = await mount();
    change(element, "startDate", "2026-09-16");
    change(element, "endDate", "2026-09-01");
    button(element, "Apply filters").click();
    await flush();
    expect(getWorkQueue).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Start date must be on or before end date");
  });

  it("pauses auto-refresh and clears its timer on disconnect", async () => {
    const element = await mount();
    const toggle = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.type === "toggle");
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(60000);
    expect(getWorkQueue).toHaveBeenCalledTimes(1);
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    document.body.removeChild(element);
    jest.advanceTimersByTime(60000);
    expect(getWorkQueue).toHaveBeenCalledTimes(1);
  });

  it("does not overlap polls and keeps prior data visible on refresh failure", async () => {
    const element = await mount();
    let reject;
    getWorkQueue.mockImplementationOnce(
      () =>
        new Promise((resolve, rejectPromise) => {
          reject = rejectPromise;
        })
    );
    jest.advanceTimersByTime(30000);
    const toggle = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.type === "toggle");
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent("change"));
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(90000);
    expect(getWorkQueue).toHaveBeenCalledTimes(2);
    reject({ body: { message: "Connection interrupted" } });
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data
    ).toHaveLength(2);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Connection interrupted");
  });

  it("retries only errors, blocks repeated clicks and refreshes after completion", async () => {
    const element = await mount();
    let finish;
    retryCheck.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    action(element, successRow);
    expect(retryCheck).not.toHaveBeenCalled();
    action(element, errorRow);
    action(element, errorRow);
    await flush();
    expect(retryCheck).toHaveBeenCalledTimes(1);
    expect(retryCheck).toHaveBeenCalledWith({ checkId: errorRow.id });
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data[0]
        .retryDisabled
    ).toBe(true);
    jest.advanceTimersByTime(60000);
    expect(getWorkQueue).toHaveBeenCalledTimes(1);
    finish({ Status__c: "Active" });
    await flush();
    expect(getWorkQueue).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector("lightning-datatable").data[0]
        .retryDisabled
    ).toBe(false);
  });

  it("reports a failed retry and resumes polling", async () => {
    const element = await mount();
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    retryCheck.mockRejectedValue({ body: { message: "Permission denied" } });
    action(element, errorRow);
    await flush();
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      title: "Retry failed",
      message: "Permission denied",
      variant: "error"
    });
    jest.advanceTimersByTime(30000);
    await flush();
    expect(getWorkQueue).toHaveBeenCalledTimes(3);
  });

  it("warns when a retry persists another eligibility error", async () => {
    const element = await mount();
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    retryCheck.mockResolvedValue({ Status__c: "Error" });
    action(element, errorRow);
    await flush();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      title: "Retry returned an error",
      variant: "warning"
    });
  });

  it("renders an empty state and an initial load error", async () => {
    getWorkQueue.mockRejectedValue({ body: { message: "No access" } });
    const element = await mount();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("No access");
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    getWorkQueue.mockResolvedValue({ rows: [], hasMore: false });
    button(element, "Refresh").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "No eligibility checks match these filters"
    );
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });
});
