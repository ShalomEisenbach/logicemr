import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocations from '@salesforce/apex/AppointmentCalendarController.getLocations';
import getGrid from '@salesforce/apex/AppointmentCalendarController.getGrid';
import rescheduleAppointment from '@salesforce/apex/AppointmentCalendarController.rescheduleAppointment';
import cancelAppointment from '@salesforce/apex/AppointmentCalendarController.cancelAppointment';
import markNoShow from '@salesforce/apex/AppointmentCalendarController.markNoShow';
import arriveAppointment from '@salesforce/apex/AppointmentCalendarController.arriveAppointment';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import APPOINTMENT_OBJECT from '@salesforce/schema/Appointment__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import TIME_ZONE from '@salesforce/i18n/timeZone';

const ANY_LOCATION = 'any';
const VIEW_DAY = 'day';
const VIEW_WEEK = 'week';
const ROW_MINUTES = 15;
const ROW_HEIGHT = 28;
const DEFAULT_START_MINUTES = 8 * 60;
const DEFAULT_END_MINUTES = 17 * 60;
const OPEN_STATUSES = new Set(['Proposed', 'Booked']);

export default class EmrAppointmentCalendar extends LightningElement {
    practitionerId;
    locationKey = ANY_LOCATION;
    locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
    viewMode = VIEW_WEEK;
    selectedDate;
    slots = [];
    hasMoreSlots = false;
    slotDurationMinutes = 20;
    errorMessage;
    isLoading = false;
    isWorking = false;

    showBookingModal = false;
    bookingSlotPending;
    showActionModal = false;
    selectedSlot;
    rescheduleAppointmentId;

    viewOptions = [
        { label: 'Day', value: VIEW_DAY },
        { label: 'Week', value: VIEW_WEEK }
    ];

    connectedCallback() {
        this.selectedDate = civilDateKey(new Date());
        this.loadLocations();
    }

    renderedCallback() {
        if (!this.showBookingModal || !this.bookingSlotPending) {
            return;
        }
        const booking = this.template.querySelector('c-emr-appointment-booking');
        if (booking?.beginFromSlot) {
            booking.beginFromSlot(this.bookingSlotPending);
            this.bookingSlotPending = undefined;
        }
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

    get encounterObjectApiName() {
        return ENCOUNTER_OBJECT.objectApiName;
    }

    get isBusy() {
        return this.isLoading || this.isWorking;
    }

    get isWeek() {
        return this.viewMode === VIEW_WEEK;
    }

    get canLoadGrid() {
        return !!(this.practitionerId || (this.locationKey && this.locationKey !== ANY_LOCATION));
    }

    get rangeLabel() {
        if (!this.selectedDate) {
            return '';
        }
        const duration = this.slotDurationMinutes ? ` · ${this.slotDurationMinutes}-minute slots` : '';
        if (this.isWeek) {
            const start = startOfWeek(parseIsoDate(this.selectedDate));
            const end = addDays(start, 6);
            return `${formatShortDate(start)} – ${formatShortDate(end)}${duration}`;
        }
        return `${formatLongDate(parseIsoDate(this.selectedDate))}${duration}`;
    }

    get hasSlots() {
        return this.slots && this.slots.length > 0;
    }

    get showGrid() {
        return this.canLoadGrid && this.hasSlots;
    }

    get showEmptyFilter() {
        return !this.canLoadGrid && !this.isLoading;
    }

    get showEmptySlots() {
        return this.canLoadGrid && !this.isLoading && !this.hasSlots && !this.errorMessage;
    }

    get isRescheduleMode() {
        return !!this.rescheduleAppointmentId;
    }

    get gridClass() {
        return this.isWeek ? 'grid grid_week' : 'grid grid_day';
    }

    get dayColumns() {
        const days = this.visibleDays();
        const slotsByDay = groupSlotsByDay(this.slots);
        const bounds = timeBounds(this.slots);
        const timeRows = buildTimeRows(bounds.startMinutes, bounds.endMinutes);
        const totalHeight = timeRows.length * ROW_HEIGHT;

        return days.map((day) => {
            const key = toIsoDate(day);
            const daySlots = assignLanes(slotsByDay[key] || []);
            return {
                key,
                label: formatDayHeader(day),
                weekday: formatWeekday(day),
                dateLabel: String(day.getDate()),
                headerClass: civilDateKey(new Date()) === key ? 'day-header day-header_today' : 'day-header',
                bodyStyle: `height:${totalHeight}px`,
                slots: daySlots.map((slot) => this.toSlotRender(slot, bounds.startMinutes, daySlots.length ? Math.max(...daySlots.map((row) => row.laneCount)) : 1))
            };
        });
    }

    get timeLabels() {
        const bounds = timeBounds(this.slots);
        return buildTimeRows(bounds.startMinutes, bounds.endMinutes).map((row) => ({
            key: String(row.minutes),
            label: row.label,
            className: row.label ? 'time-tick time-tick_label' : 'time-tick',
            style: `height:${ROW_HEIGHT}px`
        }));
    }

    get selectedAppointment() {
        return this.selectedSlot?.appointment;
    }

    get selectedPatientName() {
        return this.selectedAppointment?.patientName || 'Appointment';
    }

    get selectedAppointmentName() {
        return this.selectedAppointment?.name || '';
    }

    get selectedAppointmentId() {
        return this.selectedAppointment?.id;
    }

    get selectedPatientId() {
        return this.selectedAppointment?.patientId;
    }

    get selectedEncounterId() {
        return this.selectedAppointment?.encounterId;
    }

    get selectedEncounterName() {
        return this.selectedAppointment?.encounterName || 'Encounter';
    }

    get selectedStatus() {
        return this.selectedAppointment?.status || '';
    }

    get selectedType() {
        return this.selectedAppointment?.appointmentType || '';
    }

    get selectedReason() {
        return this.selectedAppointment?.reason || '';
    }

    get selectedWhen() {
        if (!this.selectedSlot) {
            return '';
        }
        return `${this.formatDateTime(this.selectedSlot.startTime)} – ${this.formatTime(this.selectedSlot.endTime)}`;
    }

    get selectedWhere() {
        const parts = [];
        if (this.selectedSlot?.locationName) {
            parts.push(this.selectedSlot.locationName);
        }
        if (this.selectedSlot?.practitionerName) {
            parts.push(this.selectedSlot.practitionerName);
        }
        return parts.join(' · ');
    }

    get canReschedule() {
        return OPEN_STATUSES.has(this.selectedStatus);
    }

    get canCancel() {
        return OPEN_STATUSES.has(this.selectedStatus) || this.selectedStatus === 'Arrived';
    }

    get canNoShow() {
        return OPEN_STATUSES.has(this.selectedStatus);
    }

    get canArrive() {
        return OPEN_STATUSES.has(this.selectedStatus) && !this.selectedEncounterId;
    }

    async handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
        this.errorMessage = undefined;
        await this.loadLocations();
        await this.loadGrid();
    }

    handleLocationChange(event) {
        this.locationKey = event.detail.value;
        this.errorMessage = undefined;
        this.loadGrid();
    }

    handleViewChange(event) {
        this.viewMode = event.detail.value;
        this.loadGrid();
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this.loadGrid();
    }

    handlePrev() {
        const delta = this.isWeek ? -7 : -1;
        this.selectedDate = toIsoDate(addDays(parseIsoDate(this.selectedDate), delta));
        this.loadGrid();
    }

    handleNext() {
        const delta = this.isWeek ? 7 : 1;
        this.selectedDate = toIsoDate(addDays(parseIsoDate(this.selectedDate), delta));
        this.loadGrid();
    }

    handleToday() {
        this.selectedDate = civilDateKey(new Date());
        this.loadGrid();
    }

    handleRefresh() {
        this.loadGrid();
    }

    handleSlotClick(event) {
        const slotId = event.currentTarget.dataset.slotId;
        const slot = this.slots.find((row) => row.id === slotId);
        if (!slot) {
            return;
        }
        if (slot.status === 'Blocked') {
            return;
        }
        if (this.isRescheduleMode) {
            if (slot.status === 'Free') {
                this.completeReschedule(slot);
            }
            return;
        }
        if (slot.status === 'Free') {
            this.openBooking(slot);
            return;
        }
        if (slot.appointment) {
            this.selectedSlot = slot;
            this.showActionModal = true;
        }
    }

    handleCloseBooking() {
        this.showBookingModal = false;
        this.bookingSlotPending = undefined;
    }

    handleBooked() {
        this.showBookingModal = false;
        this.bookingSlotPending = undefined;
        this.loadGrid();
    }

    handleCloseActions() {
        this.showActionModal = false;
    }

    handleStartReschedule() {
        if (!this.canReschedule || !this.selectedAppointmentId) {
            return;
        }
        this.rescheduleAppointmentId = this.selectedAppointmentId;
        this.showActionModal = false;
    }

    handleCancelReschedule() {
        this.rescheduleAppointmentId = undefined;
    }

    async handleCancelAppointment() {
        if (!this.canCancel || !this.selectedAppointmentId) {
            return;
        }
        await this.runAction(
            () => cancelAppointment({ appointmentId: this.selectedAppointmentId }),
            'Appointment cancelled'
        );
    }

    async handleNoShow() {
        if (!this.canNoShow || !this.selectedAppointmentId) {
            return;
        }
        await this.runAction(
            () => markNoShow({ appointmentId: this.selectedAppointmentId }),
            'Marked no show'
        );
    }

    async handleArrive() {
        if (!this.canArrive || !this.selectedAppointmentId) {
            return;
        }
        await this.runAction(async () => {
            const result = await arriveAppointment({ appointmentId: this.selectedAppointmentId });
            return result;
        }, 'Patient arrived');
    }

    async loadLocations() {
        try {
            const names = (await getLocations({ practitionerId: this.practitionerId || null })) || [];
            this.locationOptions = [
                { label: 'Any location', value: ANY_LOCATION },
                ...names.map((name) => ({ label: name, value: name }))
            ];
            if (this.locationKey !== ANY_LOCATION && !names.includes(this.locationKey)) {
                this.locationKey = ANY_LOCATION;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    async loadGrid() {
        if (!this.canLoadGrid || !this.selectedDate) {
            this.slots = [];
            this.hasMoreSlots = false;
            return;
        }
        const range = this.dateRange();
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const view = await getGrid({
                practitionerId: this.practitionerId || null,
                locationName: this.locationKey === ANY_LOCATION ? null : this.locationKey,
                rangeStart: range.start,
                rangeEnd: range.end
            });
            this.slots = view?.slots || [];
            this.hasMoreSlots = !!view?.hasMore;
            this.slotDurationMinutes = view?.slotDurationMinutes || 20;
        } catch (error) {
            this.slots = [];
            this.hasMoreSlots = false;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    openBooking(slot) {
        this.dispatchEvent(
            new CustomEvent('bookslot', {
                bubbles: true,
                composed: true,
                detail: {
                    slotId: slot.id,
                    startTime: slot.startTime,
                    endTime: slot.endTime,
                    locationName: slot.locationName,
                    practitionerId: slot.practitionerId,
                    practitionerName: slot.practitionerName
                }
            })
        );
        this.bookingSlotPending = slot;
        this.showBookingModal = true;
    }

    async completeReschedule(slot) {
        this.isWorking = true;
        this.errorMessage = undefined;
        try {
            const result = await rescheduleAppointment({
                appointmentId: this.rescheduleAppointmentId,
                newSlotId: slot.id
            });
            if (result?.success === false) {
                this.errorMessage = result.reason || 'This slot is no longer available.';
                return;
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Appointment rescheduled',
                    message: 'The previous slot is Free and the new slot is Busy.',
                    variant: 'success'
                })
            );
            this.rescheduleAppointmentId = undefined;
            await this.loadGrid();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isWorking = false;
        }
    }

    async runAction(action, title) {
        this.isWorking = true;
        this.errorMessage = undefined;
        try {
            const result = await action();
            if (result?.success === false) {
                this.errorMessage = result.reason || 'Unable to update the calendar.';
                return;
            }
            const message = result?.encounterName
                ? `Encounter ${result.encounterName} created.`
                : result?.appointmentName || 'Updated.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message,
                    variant: 'success'
                })
            );
            this.showActionModal = false;
            await this.loadGrid();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isWorking = false;
        }
    }

    toSlotRender(slot, gridStartMinutes, laneCount) {
        const start = minutesOfDay(slot.startTime);
        const end = minutesOfDay(slot.endTime);
        const duration = Math.max(end - start, ROW_MINUTES);
        const top = ((start - gridStartMinutes) / ROW_MINUTES) * ROW_HEIGHT;
        const height = Math.max((duration / ROW_MINUTES) * ROW_HEIGHT - 2, 18);
        const lanes = laneCount || slot.laneCount || 1;
        const lane = slot.lane || 0;
        const widthPct = 100 / lanes;
        const appointment = slot.appointment;
        const isFree = slot.status === 'Free';
        const isBlocked = slot.status === 'Blocked';
        const statusClass = appointment
            ? appointmentStatusClass(appointment.status)
            : slotStatusClass(slot.status);
        const rescheduleTarget = this.isRescheduleMode && isFree;
        const title = slotTitle(slot);
        return {
            id: slot.id,
            title,
            label: slotLabel(slot),
            meta: slotMeta(slot),
            className: [
                'slot',
                statusClass,
                isFree ? 'slot_clickable' : '',
                appointment ? 'slot_clickable' : '',
                isBlocked ? 'slot_blocked' : '',
                rescheduleTarget ? 'slot_reschedule' : ''
            ]
                .filter(Boolean)
                .join(' '),
            style: `top:${top}px;height:${height}px;left:calc(${lane * widthPct}% + 2px);width:calc(${widthPct}% - 4px)`,
            disabled: isBlocked || (this.isRescheduleMode && !isFree)
        };
    }

    visibleDays() {
        const selected = parseIsoDate(this.selectedDate);
        if (!this.isWeek) {
            return [selected];
        }
        const start = startOfWeek(selected);
        return [0, 1, 2, 3, 4, 5, 6].map((offset) => addDays(start, offset));
    }

    dateRange() {
        const selected = parseIsoDate(this.selectedDate);
        if (this.isWeek) {
            const start = startOfWeek(selected);
            return { start: toIsoDate(start), end: toIsoDate(addDays(start, 6)) };
        }
        const iso = toIsoDate(selected);
        return { start: iso, end: iso };
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
        return error?.message || 'Unable to update the calendar.';
    }
}

function groupSlotsByDay(slots) {
    const grouped = {};
    (slots || []).forEach((slot) => {
        const key = civilDateKey(slot.startTime);
        if (!grouped[key]) {
            grouped[key] = [];
        }
        grouped[key].push({ ...slot });
    });
    return grouped;
}

function timeBounds(slots) {
    if (!slots || !slots.length) {
        return { startMinutes: DEFAULT_START_MINUTES, endMinutes: DEFAULT_END_MINUTES };
    }
    let minStart = Number.POSITIVE_INFINITY;
    let maxEnd = 0;
    slots.forEach((slot) => {
        minStart = Math.min(minStart, minutesOfDay(slot.startTime));
        maxEnd = Math.max(maxEnd, minutesOfDay(slot.endTime));
    });
    return {
        startMinutes: Math.floor(minStart / 60) * 60,
        endMinutes: Math.max(Math.ceil(maxEnd / 60) * 60, Math.floor(minStart / 60) * 60 + 60)
    };
}

function buildTimeRows(startMinutes, endMinutes) {
    const rows = [];
    for (let minutes = startMinutes; minutes < endMinutes; minutes += ROW_MINUTES) {
        const minuteOfHour = minutes % 60;
        rows.push({
            minutes,
            label: minuteOfHour === 0 || minuteOfHour === 30 ? formatMinutes(minutes) : ''
        });
    }
    return rows;
}

function assignLanes(slots) {
    const sorted = [...slots].sort((a, b) => new Date(a.startTime) - new Date(b.startTime));
    const laneEnds = [];
    sorted.forEach((slot) => {
        const start = new Date(slot.startTime).getTime();
        let lane = laneEnds.findIndex((end) => end <= start);
        if (lane === -1) {
            lane = laneEnds.length;
            laneEnds.push(0);
        }
        laneEnds[lane] = new Date(slot.endTime).getTime();
        slot.lane = lane;
    });
    const laneCount = Math.max(1, laneEnds.length);
    sorted.forEach((slot) => {
        slot.laneCount = laneCount;
    });
    return sorted;
}

function slotStatusClass(status) {
    if (status === 'Free') {
        return 'slot_free';
    }
    if (status === 'Blocked') {
        return 'slot_blocked-status';
    }
    return 'slot_busy';
}

function appointmentStatusClass(status) {
    if (status === 'Arrived') {
        return 'slot_arrived';
    }
    if (status === 'No Show') {
        return 'slot_noshow';
    }
    if (status === 'Fulfilled') {
        return 'slot_fulfilled';
    }
    return 'slot_booked';
}

function slotLabel(slot) {
    if (slot.appointment?.patientName) {
        return slot.appointment.patientName;
    }
    return slot.status || 'Slot';
}

function slotMeta(slot) {
    const time = formatClock(slot.startTime);
    if (slot.appointment?.appointmentType) {
        return `${time} · ${slot.appointment.appointmentType}`;
    }
    return time;
}

function slotTitle(slot) {
    const time = `${formatClock(slot.startTime)}–${formatClock(slot.endTime)}`;
    const location = slot.locationName ? ` · ${slot.locationName}` : '';
    const provider = slot.practitionerName ? ` · ${slot.practitionerName}` : '';
    if (slot.appointment) {
        return `${slot.appointment.patientName || slot.appointment.name} · ${slot.appointment.status} · ${time}${location}${provider}`;
    }
    return `${slot.status} · ${time}${location}${provider}`;
}

function formatClock(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toLocaleTimeString(undefined, {
        hour: 'numeric',
        minute: '2-digit',
        timeZone: TIME_ZONE
    });
}

function formatMinutes(totalMinutes) {
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    const date = new Date();
    date.setHours(hours, minutes, 0, 0);
    return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

function minutesOfDay(value) {
    const date = new Date(value);
    if (!TIME_ZONE) {
        return date.getHours() * 60 + date.getMinutes();
    }
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: TIME_ZONE,
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23'
    }).formatToParts(date);
    const hour = Number(parts.find((part) => part.type === 'hour')?.value || 0);
    const minute = Number(parts.find((part) => part.type === 'minute')?.value || 0);
    return hour * 60 + minute;
}

function civilDateKey(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (!TIME_ZONE) {
        return toIsoDate(date);
    }
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    }).formatToParts(date);
    const year = parts.find((part) => part.type === 'year')?.value;
    const month = parts.find((part) => part.type === 'month')?.value;
    const day = parts.find((part) => part.type === 'day')?.value;
    return `${year}-${month}-${day}`;
}

function startOfWeek(date) {
    const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const day = copy.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    copy.setDate(copy.getDate() + offset);
    return copy;
}

function addDays(date, days) {
    const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    copy.setDate(copy.getDate() + days);
    return copy;
}

function parseIsoDate(value) {
    const [year, month, day] = value.split('-').map((part) => Number(part));
    return new Date(year, month - 1, day);
}

function toIsoDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function isSameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function formatDayHeader(date) {
    return `${formatWeekday(date)} ${date.getDate()}`;
}

function formatWeekday(date) {
    return date.toLocaleDateString(undefined, { weekday: 'short' });
}

function formatShortDate(date) {
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatLongDate(date) {
    return date.toLocaleDateString(undefined, {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
        year: 'numeric'
    });
}
