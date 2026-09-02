import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocations from '@salesforce/apex/AppointmentBookingController.getLocations';
import getFreeSlots from '@salesforce/apex/AppointmentBookingController.getFreeSlots';
import bookAppointment from '@salesforce/apex/AppointmentBookingController.bookAppointment';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import APPOINTMENT_OBJECT from '@salesforce/schema/Appointment__c';

const STEP_PATIENT = 'patient';
const STEP_PROVIDER = 'provider';
const STEP_SLOT = 'slot';
const STEP_BOOK = 'book';
const ANY_LOCATION = 'any';

export default class EmrAppointmentBooking extends LightningElement {
    currentStep = STEP_PATIENT;
    quickBook = false;
    patientId;
    practitionerId;
    locationKey = ANY_LOCATION;
    locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
    rangeStart;
    rangeEnd;
    slots = [];
    hasMoreSlots = false;
    selectedSlotId;
    selectedSlot;
    selectedSlotIds = [];
    appointmentType;
    reason = '';
    booking;
    errorMessage;
    isLoading = false;
    isBooking = false;

    typeOptions = [
        { label: 'Checkup', value: 'Checkup' },
        { label: 'Emergency', value: 'Emergency' },
        { label: 'Follow-up', value: 'Follow-up' },
        { label: 'Routine', value: 'Routine' },
        { label: 'Walk-in', value: 'Walk-in' }
    ];

    slotColumns = [
        {
            label: 'Start',
            fieldName: 'startTime',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                weekday: 'short',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        {
            label: 'End',
            fieldName: 'endTime',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        },
        { label: 'Location', fieldName: 'locationName', type: 'text' }
    ];

    connectedCallback() {
        const today = new Date();
        this.rangeStart = toIsoDate(today);
        this.rangeEnd = toIsoDate(addDays(today, 13));
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    get appointmentObjectApiName() {
        return APPOINTMENT_OBJECT.objectApiName;
    }

    get isBusy() {
        return this.isLoading || this.isBooking;
    }

    get isStepPatient() {
        return this.currentStep === STEP_PATIENT;
    }

    get isStepProvider() {
        return this.currentStep === STEP_PROVIDER;
    }

    get isStepSlot() {
        return this.currentStep === STEP_SLOT;
    }

    get isStepBook() {
        return this.currentStep === STEP_BOOK;
    }

    get isQuickBook() {
        return this.quickBook;
    }

    get showBack() {
        return !this.isStepPatient && !this.booking;
    }

    get showNext() {
        return !this.isStepBook && !this.booking;
    }

    get isNextDisabled() {
        if (this.isBusy) {
            return true;
        }
        if (this.isStepPatient) {
            return !this.patientId;
        }
        if (this.isStepProvider) {
            return !this.practitionerId;
        }
        if (this.isStepSlot) {
            return !this.selectedSlotId;
        }
        return true;
    }

    get isBookDisabled() {
        return this.isBusy || !this.patientId || !this.selectedSlotId || !this.appointmentType;
    }

    get showBookButton() {
        return this.isStepBook && !this.booking;
    }

    get hasSlots() {
        return this.slots && this.slots.length > 0;
    }

    get showSlotsEmpty() {
        return this.isStepSlot && !this.isLoading && !this.hasSlots;
    }

    get slotSummary() {
        if (!this.selectedSlot) {
            return '';
        }
        const location = this.selectedSlot.locationName ? ` · ${this.selectedSlot.locationName}` : '';
        const provider = this.selectedSlot.practitionerName ? ` · ${this.selectedSlot.practitionerName}` : '';
        return `${this.formatDateTime(this.selectedSlot.startTime)} – ${this.formatTime(this.selectedSlot.endTime)}${location}${provider}`;
    }

    /**
     * Opens a compact booking form for a grid slot (used by emrAppointmentCalendar).
     * @param {object} slot Slot view: id, startTime, endTime, locationName, practitionerId, practitionerName
     */
    @api
    beginFromSlot(slot) {
        if (!slot?.id) {
            return;
        }
        this.quickBook = true;
        this.currentStep = STEP_BOOK;
        this.practitionerId = slot.practitionerId;
        this.locationKey = slot.locationName || ANY_LOCATION;
        this.selectedSlot = {
            id: slot.id,
            startTime: slot.startTime,
            endTime: slot.endTime,
            locationName: slot.locationName,
            practitionerName: slot.practitionerName,
            practitionerId: slot.practitionerId
        };
        this.selectedSlotId = slot.id;
        this.selectedSlotIds = [slot.id];
        this.patientId = undefined;
        this.appointmentType = undefined;
        this.reason = '';
        this.booking = undefined;
        this.errorMessage = undefined;
    }

    handlePatientChange(event) {
        this.patientId = event.detail.recordId;
        this.errorMessage = undefined;
        this.booking = undefined;
    }

    handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
        this.locationKey = ANY_LOCATION;
        this.clearSlotSelection();
        this.slots = [];
        this.hasMoreSlots = false;
        this.errorMessage = undefined;
        if (this.practitionerId) {
            this.loadLocations();
        } else {
            this.locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
        }
    }

    handleLocationChange(event) {
        this.locationKey = event.detail.value;
        this.clearSlotSelection();
        if (this.isStepSlot) {
            this.loadSlots();
        }
    }

    handleRangeStartChange(event) {
        this.rangeStart = event.detail.value;
        this.clearSlotSelection();
        if (this.isStepSlot) {
            this.loadSlots();
        }
    }

    handleRangeEndChange(event) {
        this.rangeEnd = event.detail.value;
        this.clearSlotSelection();
        if (this.isStepSlot) {
            this.loadSlots();
        }
    }

    handleSlotSelection(event) {
        const selected = event.detail.selectedRows || [];
        this.selectedSlot = selected.length ? selected[0] : undefined;
        this.selectedSlotId = this.selectedSlot?.id;
        this.selectedSlotIds = this.selectedSlotId ? [this.selectedSlotId] : [];
        this.errorMessage = undefined;
    }

    handleTypeChange(event) {
        this.appointmentType = event.detail.value;
        this.errorMessage = undefined;
    }

    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    async handleNext() {
        if (this.isNextDisabled) {
            return;
        }
        this.errorMessage = undefined;
        if (this.isStepPatient) {
            this.currentStep = STEP_PROVIDER;
            return;
        }
        if (this.isStepProvider) {
            this.currentStep = STEP_SLOT;
            await this.loadSlots();
            return;
        }
        if (this.isStepSlot) {
            this.currentStep = STEP_BOOK;
        }
    }

    handleBack() {
        this.errorMessage = undefined;
        if (this.isStepProvider) {
            this.currentStep = STEP_PATIENT;
        } else if (this.isStepSlot) {
            this.currentStep = STEP_PROVIDER;
        } else if (this.isStepBook) {
            this.currentStep = STEP_SLOT;
        }
    }

    async handleRefreshSlots() {
        await this.loadSlots();
    }

    async handleBook() {
        if (this.isBookDisabled) {
            return;
        }
        this.isBooking = true;
        this.errorMessage = undefined;
        try {
            this.booking = await bookAppointment({
                patientId: this.patientId,
                slotId: this.selectedSlotId,
                appointmentType: this.appointmentType,
                reason: this.reason
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Appointment booked',
                    message: this.booking.appointmentName || 'The appointment was booked.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('booked', {
                    bubbles: true,
                    composed: true,
                    detail: { ...this.booking }
                })
            );
        } catch (error) {
            this.booking = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBooking = false;
        }
    }

    handleBookAnother() {
        this.quickBook = false;
        this.currentStep = STEP_PATIENT;
        this.patientId = undefined;
        this.practitionerId = undefined;
        this.locationKey = ANY_LOCATION;
        this.locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
        this.appointmentType = undefined;
        this.reason = '';
        this.booking = undefined;
        this.errorMessage = undefined;
        this.slots = [];
        this.hasMoreSlots = false;
        this.clearSlotSelection();
        const today = new Date();
        this.rangeStart = toIsoDate(today);
        this.rangeEnd = toIsoDate(addDays(today, 13));
    }

    async loadLocations() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const names = (await getLocations({ practitionerId: this.practitionerId })) || [];
            this.locationOptions = [
                { label: 'Any location', value: ANY_LOCATION },
                ...names.map((name) => ({ label: name, value: name }))
            ];
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadSlots() {
        if (!this.practitionerId || !this.rangeStart || !this.rangeEnd) {
            this.slots = [];
            this.hasMoreSlots = false;
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const view = await getFreeSlots({
                practitionerId: this.practitionerId,
                locationName: this.locationKey === ANY_LOCATION ? null : this.locationKey,
                rangeStart: this.rangeStart,
                rangeEnd: this.rangeEnd
            });
            this.slots = view?.slots || [];
            this.hasMoreSlots = !!view?.hasMore;
            if (this.selectedSlotId && !this.slots.some((row) => row.id === this.selectedSlotId)) {
                this.clearSlotSelection();
            }
        } catch (error) {
            this.slots = [];
            this.hasMoreSlots = false;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    clearSlotSelection() {
        this.selectedSlotId = undefined;
        this.selectedSlot = undefined;
        this.selectedSlotIds = [];
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleString(undefined, {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    formatTime(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleTimeString(undefined, {
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to book the appointment.';
    }
}

function addDays(date, days) {
    const copy = new Date(date.getTime());
    copy.setDate(copy.getDate() + days);
    return copy;
}

function toIsoDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}
