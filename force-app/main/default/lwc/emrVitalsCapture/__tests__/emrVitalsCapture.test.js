import { createElement } from "lwc";
import EmrVitalsCapture from "c/emrVitalsCapture";
import saveVitals from "@salesforce/apex/VitalsCaptureController.saveVitals";
import getEncounterVitalDetails from "@salesforce/apex/VitalsCaptureController.getEncounterVitalDetails";

jest.mock(
  "@salesforce/apex/VitalsCaptureController.saveVitals",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VitalsCaptureController.getEncounterVitalDetails",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

const metricVitals = {
  temp: {
    value: 36.8,
    unit: "Cel",
    displayUnit: "°C",
    supportedUnit: true,
    minValue: 30,
    maxValue: 45
  },
  weight: {
    value: 70,
    unit: "kg",
    displayUnit: "kg",
    supportedUnit: true,
    minValue: 0.45359237,
    maxValue: 498.951607
  },
  height: {
    value: 170,
    unit: "cm",
    displayUnit: "cm",
    supportedUnit: true,
    minValue: 30.48,
    maxValue: 274.32
  },
  hr: {
    value: 72,
    unit: "/min",
    displayUnit: "/min",
    supportedUnit: true,
    minValue: 20,
    maxValue: 250
  }
};

async function mount(details = metricVitals, recordId = "encounter-one") {
  getEncounterVitalDetails.mockResolvedValueOnce(details);
  const element = createElement("c-emr-vitals-capture", {
    is: EmrVitalsCapture
  });
  element.recordId = recordId;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function inputFor(element, key) {
  return element.shadowRoot.querySelector(`lightning-input[data-key="${key}"]`);
}

function change(element, key, value) {
  const input = inputFor(element, key);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

async function autosave() {
  jest.advanceTimersByTime(400);
  await flushPromises();
}

describe("c-emr-vitals-capture unit-aware autosave", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    saveVitals.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllTimers();
    jest.useRealTimers();
    jest.resetAllMocks();
  });

  it("loads Celsius, kilograms and centimeters with their recorded units and correct bounds", async () => {
    const element = await mount();
    expect(inputFor(element, "temp").label).toBe("Temp (°C)");
    expect(inputFor(element, "temp").value).toBe("36.8");
    expect(inputFor(element, "temp").min).toBe(30);
    expect(inputFor(element, "weight").label).toBe("Weight (kg)");
    expect(inputFor(element, "weight").value).toBe("70");
    expect(inputFor(element, "height").label).toBe("Height (cm)");
    expect(inputFor(element, "height").value).toBe("170");
    expect(saveVitals).not.toHaveBeenCalled();
  });

  it("autosaves only the changed measurement and includes its explicit unit", async () => {
    const element = await mount();
    change(element, "hr", "74");
    await autosave();
    expect(saveVitals).toHaveBeenCalledTimes(1);
    expect(saveVitals).toHaveBeenCalledWith({
      encounterId: "encounter-one",
      vitals: [{ key: "hr", value: 74, unit: "/min" }]
    });
    expect(inputFor(element, "temp").value).toBe("36.8");
    expect(inputFor(element, "height").value).toBe("170");
  });

  it("saves edited metric quantities in their source units", async () => {
    const element = await mount();
    change(element, "temp", "37");
    change(element, "weight", "71");
    change(element, "height", "171");
    await autosave();
    expect(saveVitals).toHaveBeenCalledWith({
      encounterId: "encounter-one",
      vitals: [
        { key: "temp", value: 37, unit: "Cel" },
        { key: "height", value: 171, unit: "cm" },
        { key: "weight", value: 71, unit: "kg" }
      ]
    });
  });

  it("keeps unknown and missing units visible and locked without blocking unrelated edits", async () => {
    const element = await mount({
      ...metricVitals,
      temp: { value: 310, unit: "K", displayUnit: "K", supportedUnit: false },
      weight: { value: 70, unit: null, displayUnit: null, supportedUnit: false }
    });
    expect(inputFor(element, "temp").label).toBe("Temp (K)");
    expect(inputFor(element, "temp").value).toBe("310");
    expect(inputFor(element, "temp").disabled).toBe(true);
    expect(inputFor(element, "weight").label).toBe("Weight (unit missing)");
    expect(inputFor(element, "weight").disabled).toBe(true);
    expect(element.shadowRoot.textContent).toContain("requires review");
    change(element, "hr", "75");
    await autosave();
    expect(saveVitals).toHaveBeenCalledWith({
      encounterId: "encounter-one",
      vitals: [{ key: "hr", value: 75, unit: "/min" }]
    });
  });

  it("validates edited Celsius measurements in Celsius rather than Fahrenheit", async () => {
    const element = await mount();
    change(element, "temp", "29");
    await autosave();
    expect(saveVitals).not.toHaveBeenCalled();
    change(element, "temp", "37.1");
    await autosave();
    expect(saveVitals).toHaveBeenCalledWith({
      encounterId: "encounter-one",
      vitals: [{ key: "temp", value: 37.1, unit: "Cel" }]
    });
  });

  it("does not redocument a measurement when its numeric value has not changed", async () => {
    const element = await mount();
    change(element, "weight", "70.0");
    await autosave();
    expect(saveVitals).not.toHaveBeenCalled();
  });

  it("retains edits made during an in-flight save and sends them once that save finishes", async () => {
    const element = await mount();
    let finishFirst;
    saveVitals.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finishFirst = resolve;
        })
    );
    change(element, "hr", "74");
    await autosave();
    change(element, "hr", "76");
    await autosave();
    expect(saveVitals).toHaveBeenCalledTimes(1);
    finishFirst([]);
    await flushPromises();
    expect(saveVitals).toHaveBeenCalledTimes(2);
    expect(saveVitals.mock.calls[1][0].vitals).toEqual([
      { key: "hr", value: 76, unit: "/min" }
    ]);
    expect(inputFor(element, "hr").value).toBe("76");
  });

  it("cancels a pending autosave when the encounter changes", async () => {
    const element = await mount();
    change(element, "hr", "74");
    getEncounterVitalDetails.mockResolvedValueOnce({});
    element.recordId = "encounter-two";
    await flushPromises();
    await autosave();
    expect(saveVitals).not.toHaveBeenCalled();
    expect(inputFor(element, "hr").value).toBe("");
  });

  it("blocks editing until recorded units have loaded and offers a retry after load failure", async () => {
    getEncounterVitalDetails.mockRejectedValueOnce(
      new Error("Unable to load units")
    );
    const element = createElement("c-emr-vitals-capture", {
      is: EmrVitalsCapture
    });
    element.recordId = "encounter-one";
    document.body.appendChild(element);
    await flushPromises();
    expect(inputFor(element, "hr").disabled).toBe(true);
    getEncounterVitalDetails.mockResolvedValueOnce(metricVitals);
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(inputFor(element, "hr").disabled).toBe(false);
    expect(inputFor(element, "temp").label).toBe("Temp (°C)");
  });
});
