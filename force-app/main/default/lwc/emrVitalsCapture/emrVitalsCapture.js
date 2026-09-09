import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import saveVitals from '@salesforce/apex/VitalsCaptureController.saveVitals';
import getEncounterVitals from '@salesforce/apex/VitalsCaptureController.getEncounterVitals';

const SAVE_DELAY_MS = 400;

const EMPTY_VALUES = {
    systolic: '',
    diastolic: '',
    hr: '',
    rr: '',
    temp: '',
    spo2: '',
    height: '',
    weight: ''
};

const VITAL_DEFS = {
    systolic: {
        key: 'systolic',
        label: 'Systolic (mmHg)',
        display: 'Systolic blood pressure',
        unit: 'mmHg',
        loinc: '8480-6',
        min: 50,
        max: 250,
        step: '1'
    },
    diastolic: {
        key: 'diastolic',
        label: 'Diastolic (mmHg)',
        display: 'Diastolic blood pressure',
        unit: 'mmHg',
        loinc: '8462-4',
        min: 30,
        max: 160,
        step: '1'
    },
    hr: {
        key: 'hr',
        label: 'Heart rate (/min)',
        display: 'Heart rate',
        unit: '/min',
        loinc: '8867-4',
        min: 20,
        max: 250,
        step: '1'
    },
    rr: {
        key: 'rr',
        label: 'Resp. rate (/min)',
        display: 'Respiratory rate',
        unit: '/min',
        loinc: '9279-1',
        min: 4,
        max: 80,
        step: '1'
    },
    temp: {
        key: 'temp',
        label: 'Temp (°F)',
        display: 'Body temperature',
        unit: 'F',
        loinc: '8310-5',
        min: 86,
        max: 113,
        step: '0.1'
    },
    spo2: {
        key: 'spo2',
        label: 'SpO2 (%)',
        display: 'Oxygen saturation',
        unit: '%',
        loinc: '59408-5',
        min: 50,
        max: 100,
        step: '1'
    },
    height: {
        key: 'height',
        label: 'Height (in)',
        display: 'Body height',
        unit: 'in',
        loinc: '8302-2',
        min: 12,
        max: 108,
        step: '0.1'
    },
    weight: {
        key: 'weight',
        label: 'Weight (lbs)',
        display: 'Body weight',
        unit: 'lbs',
        loinc: '29463-7',
        min: 1,
        max: 1100,
        step: '0.1'
    }
};

const VITAL_ORDER = ['systolic', 'diastolic', 'hr', 'rr', 'temp', 'spo2', 'height', 'weight'];

export default class EmrVitalsCapture extends LightningElement {
    errorMessage;
    isSaving = false;
    isDirty = false;
    pendingSave = false;
    saveTimeoutId;
    loadRequestId = 0;
    _recordId;
    values = { ...EMPTY_VALUES };

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = this._recordId !== value;
        this._recordId = value;
        if (changed) {
            this.isDirty = false;
            this.values = { ...EMPTY_VALUES };
            this.errorMessage = undefined;
            this.loadExisting();
        }
    }

    get vitals() {
        return VITAL_ORDER.map((key) => {
            const def = VITAL_DEFS[key];
            const rangeMessage = `${def.display} must be between ${def.min} and ${def.max} ${def.unit}.`;
            return {
                ...def,
                value: this.values[key],
                help: `LOINC ${def.loinc}`,
                rangeMessage
            };
        });
    }

    disconnectedCallback() {
        window.clearTimeout(this.saveTimeoutId);
    }

    handleChange(event) {
        const key = event.target.dataset.key;
        this.isDirty = true;
        this.values = { ...this.values, [key]: event.detail.value };
        this.errorMessage = undefined;
        event.target.setCustomValidity('');
        event.target.reportValidity();
        this.scheduleSave();
    }

    scheduleSave() {
        window.clearTimeout(this.saveTimeoutId);
        this.saveTimeoutId = window.setTimeout(() => {
            this.persistVitals();
        }, SAVE_DELAY_MS);
    }

    async persistVitals() {
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
        try {
            await saveVitals({
                encounterId: this.recordId,
                vitals: parsed
            });
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
            if (this.pendingSave) {
                this.pendingSave = false;
                this.persistVitals();
            }
        }
    }

    async loadExisting() {
        if (!this.recordId) {
            return;
        }
        const requestId = ++this.loadRequestId;
        try {
            const latest = await getEncounterVitals({ encounterId: this.recordId });
            if (requestId !== this.loadRequestId || this.isDirty) {
                return;
            }
            const next = { ...EMPTY_VALUES };
            VITAL_ORDER.forEach((key) => {
                if (latest && latest[key] != null) {
                    next[key] = String(latest[key]);
                }
            });
            this.values = next;
        } catch (error) {
            if (requestId === this.loadRequestId) {
                this.errorMessage = this.reduceError(error);
            }
        }
    }

    collectAndValidate() {
        const inputs = this.template.querySelectorAll('lightning-input[data-key]');
        const filled = [];
        let hasInlineError = false;
        const numericByKey = {};

        inputs.forEach((input) => {
            const key = input.dataset.key;
            const def = VITAL_DEFS[key];
            const raw = input.value;
            input.setCustomValidity('');

            if (raw === '' || raw === null || raw === undefined) {
                input.reportValidity();
                return;
            }

            const value = Number(raw);
            if (Number.isNaN(value) || value < def.min || value > def.max) {
                input.setCustomValidity(
                    `${def.display} must be between ${def.min} and ${def.max} ${def.unit}.`
                );
                hasInlineError = true;
            } else {
                numericByKey[key] = value;
                filled.push({ key, value });
            }
            input.reportValidity();
        });

        const systolic = numericByKey.systolic;
        const diastolic = numericByKey.diastolic;
        if (systolic != null && diastolic != null && systolic < diastolic) {
            const message = 'Systolic blood pressure must be greater than or equal to diastolic.';
            inputs.forEach((input) => {
                if (input.dataset.key === 'systolic' || input.dataset.key === 'diastolic') {
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

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to save vitals.';
    }
}
