import { createElement } from "lwc";
import EmrAdminConsole from "c/emrAdminConsole";
import getOverview from "@salesforce/apex/AdminConsoleController.getOverview";
import saveClinicalUnits from "@salesforce/apex/AdminConsoleController.saveClinicalUnits";
import { refreshApex } from "@salesforce/apex";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/AdminConsoleController.getOverview",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getIntegrationMonitor",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getNoteTemplates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getPractitioners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.savePractitionerUsers",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getBillingOrganization",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveBillingOrganization",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveEligibilitySetting",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveCommConfig",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveClinicalUnits",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveMessageTemplate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.saveNameFormat",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.scheduleReminderJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.abortReminderJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.scheduleEligibilityJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.abortEligibilityJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.runEligibilityNow",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.enqueueNameBackfill",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.enqueueCatalogLinkBackfill",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getNameBackfillObjects",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AdminConsoleController.getCatalogLinkOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

async function mount(
  preferences = { temperatureUnit: "F", measurementSystem: "Imperial" }
) {
  const element = createElement("c-emr-admin-console", { is: EmrAdminConsole });
  document.body.appendChild(element);
  getOverview.emit({ clinicalUnits: preferences });
  await flushPromises();
  element.shadowRoot.querySelector('[data-section="clinicalUnits"]').click();
  await flushPromises();
  return element;
}

function select(element, field, value) {
  element.shadowRoot
    .querySelector(`[data-field="${field}"]`)
    .dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

function saveButton(element) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (button) => button.label === "Save vital units"
  );
}

describe("c-emr-admin-console vital units", () => {
  beforeEach(() => {
    saveClinicalUnits.mockResolvedValue({
      success: true,
      message: "Settings queued."
    });
    refreshApex.mockResolvedValue();
  });

  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.resetAllMocks();
  });

  it("loads the saved independent preferences and exposes both systems", async () => {
    const element = await mount({
      temperatureUnit: "Cel",
      measurementSystem: "Imperial"
    });
    const temperature = element.shadowRoot.querySelector(
      '[data-field="temperatureUnit"]'
    );
    const measurements = element.shadowRoot.querySelector(
      '[data-field="measurementSystem"]'
    );
    expect(temperature.value).toBe("Cel");
    expect(temperature.options.map((option) => option.value)).toEqual([
      "F",
      "Cel"
    ]);
    expect(measurements.value).toBe("Imperial");
    expect(measurements.options.map((option) => option.value)).toEqual([
      "Imperial",
      "Metric"
    ]);
    expect(saveClinicalUnits).not.toHaveBeenCalled();
  });

  it("saves Fahrenheit with metric height and weight without coupling the choices", async () => {
    const element = await mount();
    select(element, "measurementSystem", "Metric");
    saveButton(element).click();
    await flushPromises();
    expect(saveClinicalUnits).toHaveBeenCalledWith({
      temperatureUnit: "F",
      measurementSystem: "Metric"
    });
  });

  it("prevents repeated saves while a request is pending", async () => {
    const element = await mount();
    let finish;
    saveClinicalUnits.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    saveButton(element).click();
    saveButton(element).click();
    await flushPromises();
    expect(saveClinicalUnits).toHaveBeenCalledTimes(1);
    expect(saveButton(element).disabled).toBe(true);
    finish({ success: true });
    await flushPromises();
    expect(saveButton(element).disabled).toBe(false);
  });

  it("retains draft selections and reports a denied save", async () => {
    const element = await mount();
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    select(element, "temperatureUnit", "Cel");
    select(element, "measurementSystem", "Metric");
    saveClinicalUnits.mockRejectedValueOnce({
      body: { message: "Settings permission required." }
    });
    saveButton(element).click();
    await flushPromises();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      variant: "error",
      message: "Settings permission required."
    });
    expect(
      element.shadowRoot.querySelector('[data-field="temperatureUnit"]').value
    ).toBe("Cel");
    expect(
      element.shadowRoot.querySelector('[data-field="measurementSystem"]').value
    ).toBe("Metric");
    expect(saveButton(element).disabled).toBe(false);
  });

  it("reloads the persisted choices when Refresh is selected", async () => {
    const element = await mount();
    select(element, "temperatureUnit", "Cel");
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(refreshApex).toHaveBeenCalled();
    getOverview.emit({
      clinicalUnits: { temperatureUnit: "F", measurementSystem: "Metric" }
    });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('[data-field="temperatureUnit"]').value
    ).toBe("F");
    expect(
      element.shadowRoot.querySelector('[data-field="measurementSystem"]').value
    ).toBe("Metric");
  });
});
