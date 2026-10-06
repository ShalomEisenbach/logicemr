import { LightningElement, api } from "lwc";
import { RefreshEvent } from "lightning/refresh";
import saveVitals from "@salesforce/apex/VitalsCaptureController.saveVitals";
import getEncounterVitalDetails from "@salesforce/apex/VitalsCaptureController.getEncounterVitalDetails";

const SAVE_DELAY_MS = 400;

const EMPTY_VALUES = {
  systolic: "",
  diastolic: "",
  hr: "",
  rr: "",
  temp: "",
  spo2: "",
  height: "",
  weight: ""
};

const VITAL_DEFS = {
  systolic: {
    key: "systolic",
    label: "Systolic (mmHg)",
    display: "Systolic blood pressure",
    unit: "mmHg",
    loinc: "8480-6",
    min: 50,
    max: 250,
    step: "1"
  },
  diastolic: {
    key: "diastolic",
    label: "Diastolic (mmHg)",
    display: "Diastolic blood pressure",
    unit: "mmHg",
    loinc: "8462-4",
    min: 30,
    max: 160,
    step: "1"
  },
  hr: {
    key: "hr",
    label: "Heart rate (/min)",
    display: "Heart rate",
    unit: "/min",
    loinc: "8867-4",
    min: 20,
    max: 250,
    step: "1"
  },
  rr: {
    key: "rr",
    label: "Resp. rate (/min)",
    display: "Respiratory rate",
    unit: "/min",
    loinc: "9279-1",
    min: 4,
    max: 80,
    step: "1"
  },
  temp: {
    key: "temp",
    label: "Temp (°F)",
    display: "Body temperature",
    unit: "F",
    loinc: "8310-5",
    min: 86,
    max: 113,
    step: "0.1"
  },
  spo2: {
    key: "spo2",
    label: "SpO2 (%)",
    display: "Oxygen saturation",
    unit: "%",
    loinc: "59408-5",
    min: 50,
    max: 100,
    step: "1"
  },
  height: {
    key: "height",
    label: "Height (in)",
    display: "Body height",
    unit: "in",
    loinc: "8302-2",
    min: 12,
    max: 108,
    step: "0.1"
  },
  weight: {
    key: "weight",
    label: "Weight (lbs)",
    display: "Body weight",
    unit: "lbs",
    loinc: "29463-7",
    min: 1,
    max: 1100,
    step: "0.1"
  }
};

const VITAL_ORDER = [
  "systolic",
  "diastolic",
  "hr",
  "rr",
  "temp",
  "spo2",
  "height",
  "weight"
];

export default class EmrVitalsCapture extends LightningElement {
  errorMessage;
  isSaving = false;
  isLoading = false;
  loadFailed = false;
  pendingSave = false;
  saveTimeoutId;
  loadRequestId = 0;
  saveRequestId = 0;
  _recordId;
  values = { ...EMPTY_VALUES };
  savedValues = { ...EMPTY_VALUES };
  details = {};
  dirtyKeys = [];

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = this._recordId !== value;
    this._recordId = value;
    if (changed) {
      window.clearTimeout(this.saveTimeoutId);
      this.loadRequestId += 1;
      this.saveRequestId += 1;
      this.isSaving = false;
      this.pendingSave = false;
      this.dirtyKeys = [];
      this.values = { ...EMPTY_VALUES };
      this.savedValues = { ...EMPTY_VALUES };
      this.details = {};
      this.errorMessage = undefined;
      this.loadFailed = false;
      this.loadExisting();
    }
  }

  get vitals() {
    return VITAL_ORDER.map((key) => {
      const def = VITAL_DEFS[key];
      const detail = this.details[key];
      const unit = detail ? detail.unit : def.unit;
      const displayUnit = detail
        ? detail.displayUnit || unit || "unit missing"
        : def.label.match(/\((.*)\)$/)[1];
      const min = detail ? detail.minValue : def.min;
      const max = detail ? detail.maxValue : def.max;
      const unsupported = !!detail && detail.supportedUnit !== true;
      const rangeMessage = `${def.display} must be between ${min} and ${max} ${displayUnit}.`;
      return {
        ...def,
        label: `${def.label.replace(/\s*\(.*\)$/, "")} (${displayUnit})`,
        unit,
        min,
        max,
        step: detail ? "any" : def.step,
        value: this.values[key],
        help: `LOINC ${def.loinc}`,
        disabled: this.isLoading || this.loadFailed || unsupported,
        unitWarning: unsupported
          ? `Recorded unit ${unit || "(missing)"} requires review before this measurement can be edited.`
          : undefined,
        rangeMessage
      };
    });
  }

  disconnectedCallback() {
    window.clearTimeout(this.saveTimeoutId);
    this.loadRequestId += 1;
    this.saveRequestId += 1;
    this.pendingSave = false;
  }

  handleChange(event) {
    const key = event.target.dataset.key;
    if (
      this.isLoading ||
      this.loadFailed ||
      this.details[key]?.supportedUnit === false
    ) {
      return;
    }
    const value = event.detail.value;
    this.values = { ...this.values, [key]: value };
    const unchanged = this.sameValue(value, this.savedValues[key]);
    this.dirtyKeys = unchanged
      ? this.dirtyKeys.filter((dirtyKey) => dirtyKey !== key)
      : [...new Set([...this.dirtyKeys, key])];
    this.errorMessage = undefined;
    event.target.setCustomValidity("");
    event.target.reportValidity();
    this.scheduleSave();
  }

  scheduleSave() {
    window.clearTimeout(this.saveTimeoutId);
    // Debounce autosave so a partially entered vital is not saved on every keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.saveTimeoutId = window.setTimeout(() => {
      this.persistVitals();
    }, SAVE_DELAY_MS);
  }

  async persistVitals() {
    if (this.isLoading || this.loadFailed || !this.recordId) {
      return;
    }
    if (this.isSaving) {
      this.pendingSave = true;
      return;
    }

    this.errorMessage = undefined;
    const parsed = this.collectAndValidate();
    if (!parsed) {
      return;
    }

    this.isSaving = true;
    const requestId = ++this.saveRequestId;
    const encounterId = this.recordId;
    try {
      await saveVitals({
        encounterId,
        vitals: parsed
      });
      if (requestId !== this.saveRequestId || encounterId !== this.recordId) {
        return;
      }
      const saved = { ...this.savedValues };
      for (const row of parsed) {
        saved[row.key] = String(row.value);
      }
      this.savedValues = saved;
      this.dirtyKeys = this.dirtyKeys.filter(
        (key) => !this.sameValue(this.values[key], saved[key])
      );
      this.dispatchEvent(new RefreshEvent());
    } catch (error) {
      if (requestId === this.saveRequestId && encounterId === this.recordId) {
        this.errorMessage = this.reduceError(error);
      }
    } finally {
      if (requestId === this.saveRequestId && encounterId === this.recordId) {
        this.isSaving = false;
        if (this.pendingSave) {
          this.pendingSave = false;
          this.persistVitals();
        }
      }
    }
  }

  async loadExisting() {
    if (!this.recordId) {
      this.isLoading = false;
      return;
    }
    const requestId = ++this.loadRequestId;
    this.isLoading = true;
    this.loadFailed = false;
    try {
      const latest = await getEncounterVitalDetails({
        encounterId: this.recordId
      });
      if (requestId !== this.loadRequestId) {
        return;
      }
      const next = { ...EMPTY_VALUES };
      VITAL_ORDER.forEach((key) => {
        if (latest?.[key]?.value != null) {
          next[key] = String(latest[key].value);
        }
      });
      this.values = next;
      this.savedValues = { ...next };
      this.details = latest || {};
      this.errorMessage = undefined;
    } catch (error) {
      if (requestId === this.loadRequestId) {
        this.loadFailed = true;
        this.errorMessage = this.reduceError(error);
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoading = false;
      }
    }
  }

  handleReload() {
    this.loadExisting();
  }

  collectAndValidate() {
    const inputs = this.template.querySelectorAll("lightning-input[data-key]");
    const filled = [];
    let hasInlineError = false;
    const numericByKey = {};
    const defs = new Map(this.vitals.map((vital) => [vital.key, vital]));

    inputs.forEach((input) => {
      const key = input.dataset.key;
      const def = defs.get(key);
      const raw = input.value;
      if (
        !def.disabled &&
        raw !== "" &&
        raw !== null &&
        raw !== undefined &&
        Number.isFinite(Number(raw))
      ) {
        numericByKey[key] = Number(raw);
      }
      if (!this.dirtyKeys.includes(key) || def.disabled) {
        return;
      }
      input.setCustomValidity("");

      if (raw === "" || raw === null || raw === undefined) {
        if (this.savedValues[key] !== "") {
          input.setCustomValidity(
            "Enter a value to update this recorded vital."
          );
          hasInlineError = true;
        }
        input.reportValidity();
        return;
      }

      const value = Number(raw);
      if (!Number.isFinite(value) || value < def.min || value > def.max) {
        input.setCustomValidity(
          `${def.display} must be between ${def.min} and ${def.max} ${def.unit}.`
        );
        hasInlineError = true;
      } else {
        filled.push({ key, value, unit: def.unit });
      }
      input.reportValidity();
    });

    const systolic = numericByKey.systolic;
    const diastolic = numericByKey.diastolic;
    if (
      (this.dirtyKeys.includes("systolic") ||
        this.dirtyKeys.includes("diastolic")) &&
      systolic != null &&
      diastolic != null &&
      systolic < diastolic
    ) {
      const message =
        "Systolic blood pressure must be greater than or equal to diastolic.";
      inputs.forEach((input) => {
        if (
          input.dataset.key === "systolic" ||
          input.dataset.key === "diastolic"
        ) {
          input.setCustomValidity(message);
          input.reportValidity();
        }
      });
      hasInlineError = true;
    }

    if (hasInlineError || filled.length === 0) {
      return null;
    }
    return filled;
  }

  sameValue(left, right) {
    const leftEmpty = left === "" || left === null || left === undefined;
    const rightEmpty = right === "" || right === null || right === undefined;
    return leftEmpty || rightEmpty
      ? leftEmpty === rightEmpty
      : Number(left) === Number(right);
  }

  reduceError(error) {
    if (error?.body?.message) {
      return error.body.message;
    }
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }
    return error?.message || "Unable to save vitals.";
  }
}
