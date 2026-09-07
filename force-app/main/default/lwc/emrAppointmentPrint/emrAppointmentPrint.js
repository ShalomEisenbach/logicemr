import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrintPayload from '@salesforce/apex/AppointmentCommunicationController.getPrintPayload';
import logPrint from '@salesforce/apex/AppointmentCommunicationController.logPrint';

export default class EmrAppointmentPrint extends LightningElement {
    @api recordId;
    @api appointmentId;

    payload;
    errorMessage;
    isBusy = false;
    wiredResult;

    get effectiveId() {
        return this.appointmentId || this.recordId;
    }

    @wire(getPrintPayload, { appointmentId: '$effectiveId' })
    wiredPayload(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.payload = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.payload = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasPayload() {
        return !!this.payload;
    }

    get emptyValue() {
        return '—';
    }

    get patientName() {
        return this.payload?.patientName || this.emptyValue;
    }

    get mrn() {
        return this.payload?.mrn || this.emptyValue;
    }

    get practitionerName() {
        return this.payload?.practitionerName || this.emptyValue;
    }

    get locationName() {
        return this.payload?.locationName || this.emptyValue;
    }

    get appointmentType() {
        return this.payload?.appointmentType || this.emptyValue;
    }

    get reason() {
        return this.payload?.reason || this.emptyValue;
    }

    get status() {
        return this.payload?.status || this.emptyValue;
    }

    get startTime() {
        return this.payload?.startTime || '';
    }

    get endTime() {
        return this.payload?.endTime || '';
    }

    async handlePrint() {
        if (!this.effectiveId || this.isBusy) {
            return;
        }
        this.isBusy = true;
        try {
            await logPrint({ appointmentId: this.effectiveId });
            window.print();
            this.dispatchEvent(new CustomEvent('printed'));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Print failed',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load appointment.';
    }
}
