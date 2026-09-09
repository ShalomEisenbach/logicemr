import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocations from '@salesforce/apex/AppointmentBookingController.getLocations';
import getAvailableProviders from '@salesforce/apex/AppointmentBookingController.getAvailableProviders';
import bookAppointment from '@salesforce/apex/AppointmentBookingController.bookAppointment';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import APPOINTMENT_OBJECT from '@salesforce/schema/Appointment__c';
import TIME_ZONE from '@salesforce/i18n/timeZone';

const STEP_PATIENT = 'patient';
const STEP_DATE = 'date';
const STEP_PROVIDER = 'provider';
const STEP_SLOT = 'slot';
const STEP_BOOK = 'book';
const ANY_LOCATION = 'any';

export default class EmrAppointmentBooking extends LightningElement {
    currentStep = STEP_PATIENT;
    quickBook = false;
    patientLocked = false;
    patientId;
    practitionerId;
    locationKey = ANY_LOCATION;
    locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
    rangeStart;
    rangeEnd;
    providers = [];
    showAllProviders = true;
    calendarStarted = false;
    selectedSlotId;
    selectedSlot;
    selectedSlotIds = [];
    selectedProviderIds = [];
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

    providerColumns = [
        { label: 'Provider', fieldName: 'practitionerName', type: 'text' },
        { label: 'Specialty', fieldName: 'specialty', type: 'text' },
        { label: 'Locations', fieldName: 'locationNames', type: 'text' },
        { label: 'Free slots', fieldName: 'freeSlotCount', type: 'number', cellAttributes: { alignment: 'left' } },
        {
            label: 'Earliest',
            fieldName: 'earliestStart',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                weekday: 'short',
                hour: '2-digit',
                minute: '2-digit'
            }
        }
    ];

    connectedCallback() {
        this.resetDateRange();
        this.loadLocations();
    }

    renderedCallback() {
        if (!this.isStepSlot || this.calendarStarted || this.quickBook) {
            return;
        }
        const calendar = this.template.querySelector('c-emr-enhanced-calendar');
        if (calendar?.beginBooking) {
            calendar.beginBooking({
                practitionerIds: this.selectedProviderIds,
                practitionerId: this.practitionerId,
                locationKey: this.locationKey,
                selectedDate: this.rangeStart,
                patientId: this.patientId,
                viewMode: this.rangeStart && this.rangeEnd && this.rangeStart === this.rangeEnd ? 'day' : 'week'
            });
            this.calendarStarted = true;
        }
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
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

    get isStepDate() {
        return this.currentStep === STEP_DATE;
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

    get showPatientStep() {
        return this.isStepPatient && !this.patientLocked;
    }

    get showBack() {
        if (this.booking || this.isStepPatient) {
            return false;
        }
        return !(this.patientLocked && this.isStepDate);
    }

    get showNext() {
        return !this.isStepBook && !this.isStepSlot && !this.booking;
    }

    get isDateRangeInvalid() {
        return !this.rangeStart || !this.rangeEnd || this.rangeEnd < this.rangeStart;
    }

    get isNextDisabled() {
        if (this.isBusy) {
            return true;
        }
        if (this.isStepPatient) {
            return !this.patientId;
        }
        if (this.isStepDate) {
            return this.isDateRangeInvalid;
        }
        if (this.isStepProvider) {
            return !this.selectedProviderIds.length;
        }
        return true;
    }

    get isBookDisabled() {
        return this.isBusy || !this.patientId || !this.selectedSlotId || !this.appointmentType;
    }

    get showBookButton() {
        return this.isStepBook && !this.booking;
    }

    get hasProviders() {
        return this.providers && this.providers.length > 0;
    }

    get showProvidersEmpty() {
        return this.isStepProvider && !this.isLoading && !this.hasProviders;
    }

    get dateRangeSummary() {
        if (!this.rangeStart || !this.rangeEnd) {
            return '';
        }
        const location = this.locationKey && this.locationKey !== ANY_LOCATION ? ` · ${this.locationKey}` : '';
        return `Availability from ${this.formatDate(this.rangeStart)} to ${this.formatDate(this.rangeEnd)}${location}`;
    }

    get providersEmptyMessage() {
        if (this.showAllProviders) {
            return 'No active providers found.';
        }
        return 'No providers have free slots in the selected dates. Turn on Show all providers to choose anyone.';
    }

    get selectedProviderNames() {
        const selected = new Set(this.selectedProviderIds);
        return this.providers
            .filter((row) => selected.has(row.practitionerId))
            .map((row) => row.practitionerName)
            .filter(Boolean)
            .join(', ');
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
     * Starts booking for a known patient (used by emrAppointmentPanel).
     * Skips the patient step and keeps that patient locked.
     * @param {string} patientId Patient__c Id
     */
    @api
    beginForPatient(patientId) {
        if (!patientId) {
            return;
        }
        this.patientLocked = true;
        this.quickBook = false;
        this.currentStep = STEP_DATE;
        this.patientId = patientId;
        this.resetProviderState();
        this.appointmentType = undefined;
        this.reason = '';
        this.booking = undefined;
        this.errorMessage = undefined;
        this.calendarStarted = false;
        this.resetDateRange();
        this.loadLocations();
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
        this.patientLocked = false;
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
        this.selectedProviderIds = slot.practitionerId ? [slot.practitionerId] : [];
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

    handlePatientCreated(event) {
        this.patientId = event.detail?.patientId;
        this.errorMessage = undefined;
        this.booking = undefined;
    }

    handleLocationChange(event) {
        this.locationKey = event.detail.value;
        this.resetProviderState();
        this.errorMessage = undefined;
    }

    handleRangeStartChange(event) {
        this.rangeStart = event.detail.value;
        this.resetProviderState();
        this.errorMessage = undefined;
    }

    handleRangeEndChange(event) {
        this.rangeEnd = event.detail.value;
        this.resetProviderState();
        this.errorMessage = undefined;
    }

    handleProviderSelection(event) {
        const selected = event.detail.selectedRows || [];
        this.selectedProviderIds = selected.map((row) => row.practitionerId).filter(Boolean);
        this.practitionerId = this.selectedProviderIds[0];
        this.clearSlotSelection();
        this.calendarStarted = false;
        this.errorMessage = undefined;
    }

    async handleShowAllProvidersChange(event) {
        this.showAllProviders = event.detail.checked;
        await this.loadProviders();
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
            this.currentStep = STEP_DATE;
            return;
        }
        if (this.isStepDate) {
            this.currentStep = STEP_PROVIDER;
            await this.loadProviders();
            return;
        }
        if (this.isStepProvider) {
            this.calendarStarted = false;
            this.currentStep = STEP_SLOT;
        }
    }

    handleBack() {
        this.errorMessage = undefined;
        if (this.isStepDate) {
            this.currentStep = STEP_PATIENT;
        } else if (this.isStepProvider) {
            this.currentStep = STEP_DATE;
        } else if (this.isStepSlot) {
            this.calendarStarted = false;
            this.currentStep = STEP_PROVIDER;
        } else if (this.isStepBook) {
            this.calendarStarted = false;
            this.currentStep = STEP_SLOT;
        }
    }

    async handleRefreshProviders() {
        await this.loadProviders();
    }

    handleCalendarBooked(event) {
        const detail = event.detail || {};
        this.booking = {
            appointmentId: detail.appointmentId,
            appointmentName: detail.appointmentName
        };
        this.currentStep = STEP_BOOK;
        this.calendarStarted = false;
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
                    message:
                        (this.booking.appointmentName || 'The appointment was booked.') +
                        ' Confirmation queued.',
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
        if (this.patientLocked && this.patientId) {
            this.beginForPatient(this.patientId);
            return;
        }
        this.patientLocked = false;
        this.currentStep = STEP_PATIENT;
        this.patientId = undefined;
        this.resetProviderState();
        this.locationKey = ANY_LOCATION;
        this.appointmentType = undefined;
        this.reason = '';
        this.booking = undefined;
        this.errorMessage = undefined;
        this.calendarStarted = false;
        this.resetDateRange();
        this.loadLocations();
    }

    async loadLocations() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const names = (await getLocations({ practitionerId: null })) || [];
            this.locationOptions = [
                { label: 'Any location', value: ANY_LOCATION },
                ...names.map((name) => ({ label: name, value: name }))
            ];
            if (this.locationKey !== ANY_LOCATION && !names.includes(this.locationKey)) {
                this.locationKey = ANY_LOCATION;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadProviders() {
        if (this.isDateRangeInvalid) {
            this.providers = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.providers = (await getAvailableProviders({
                rangeStart: this.rangeStart,
                rangeEnd: this.rangeEnd,
                locationName: this.locationKey === ANY_LOCATION ? null : this.locationKey,
                includeUnavailable: this.showAllProviders
            })) || [];
            const availableIds = new Set(this.providers.map((row) => row.practitionerId));
            this.selectedProviderIds = this.selectedProviderIds.filter((id) => availableIds.has(id));
            this.practitionerId = this.selectedProviderIds[0];
        } catch (error) {
            this.providers = [];
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    resetDateRange() {
        const today = new Date();
        this.rangeStart = toIsoDate(today);
        this.rangeEnd = toIsoDate(addDays(today, 13));
    }

    resetProviderState() {
        this.practitionerId = undefined;
        this.selectedProviderIds = [];
        this.providers = [];
        this.calendarStarted = false;
        this.clearSlotSelection();
    }

    clearSlotSelection() {
        this.selectedSlotId = undefined;
        this.selectedSlot = undefined;
        this.selectedSlotIds = [];
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        return new Date(`${value}T00:00:00`).toLocaleDateString(undefined, {
            weekday: 'short',
            month: 'short',
            day: 'numeric'
        });
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
            minute: '2-digit',
            timeZone: TIME_ZONE
        });
    }

    formatTime(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleTimeString(undefined, {
            hour: 'numeric',
            minute: '2-digit',
            timeZone: TIME_ZONE
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
