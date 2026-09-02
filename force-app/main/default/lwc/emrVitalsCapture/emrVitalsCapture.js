import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import saveVitals from '@salesforce/apex/VitalsCaptureController.saveVitals';

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
        label: 'Temp (°C)',
        display: 'Body temperature',
        unit: 'Cel',
        loinc: '8310-5',
        min: 30,
        max: 45,
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
        label: 'Height (cm)',
        display: 'Body height',
        unit: 'cm',
        loinc: '8302-2',
        min: 30,
        max: 250,
        step: '0.1'
    },
    weight: {
        key: 'weight',
        label: 'Weight (kg)',
        display: 'Body weight',
        unit: 'kg',
        loinc: '29463-7',
        min: 0.5,
        max: 500,
        step: '0.1'
    }
};

const VITAL_ORDER = ['systolic', 'diastolic', 'hr', 'rr', 'temp', 'spo2', 'height', 'weight'];

export default class EmrVitalsCapture extends LightningElement {
    @api recordId;

    errorMessage;
    isSaving = false;
    values = {
        systolic: '',
        diastolic: '',
        hr: '',
        rr: '',
        temp: '',
        spo2: '',
        height: '',
        weight: ''
    };

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

    handleChange(event) {
        const key = event.target.dataset.key;
        this.values = { ...this.values, [key]: event.detail.value };
        this.errorMessage = undefined;
        event.target.setCustomValidity('');
        event.target.reportValidity();
    }

    async handleSave() {
        if (this.isSaving) {
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
            this.values = {
                systolic: '',
                diastolic: '',
                hr: '',
                rr: '',
                temp: '',
                spo2: '',
                height: '',
                weight: ''
            };
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Vitals saved',
                    message: `${parsed.length} observation${parsed.length === 1 ? '' : 's'} recorded.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
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

        if (hasInlineError) {
            return null;
        }
        if (filled.length === 0) {
            this.errorMessage = 'Enter at least one vital.';
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
