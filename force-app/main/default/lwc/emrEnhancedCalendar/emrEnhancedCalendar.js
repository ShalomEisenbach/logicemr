import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLocations from '@salesforce/apex/AppointmentCalendarController.getLocations';
import getGrid from '@salesforce/apex/AppointmentCalendarController.getGrid';
import getActiveSchedules from '@salesforce/apex/AppointmentCalendarController.getActiveSchedules';
import bookAppointment from '@salesforce/apex/AppointmentCalendarController.bookAppointment';
import rescheduleAppointment from '@salesforce/apex/AppointmentCalendarController.rescheduleAppointment';
import cancelAppointment from '@salesforce/apex/AppointmentCalendarController.cancelAppointment';
import markNoShow from '@salesforce/apex/AppointmentCalendarController.markNoShow';
import arriveAppointment from '@salesforce/apex/AppointmentCalendarController.arriveAppointment';
import createAdHocSlots from '@salesforce/apex/AppointmentCalendarController.createAdHocSlots';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import ENCOUNTER_OBJECT from '@salesforce/schema/Encounter__c';
import { recordViewPageRef } from 'c/emrNavigationUtils';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import {
    APPT_ARRIVED,
    APPT_CANCELLED,
    APPT_NO_SHOW,
    DEFAULT_DURATION,
    DRAG_THRESHOLD,
    ROW_HEIGHT,
    SLOT_BLOCKED,
    SLOT_FREE,
    addDays,
    applyOptimisticBook,
    applyOptimisticMove,
    applyOptimisticPaint,
    applyOptimisticStatus,
    buildTimeRows,
    canArrive,
    canCancel,
    canDragBlock,
    canNoShow,
    civilDateKey,
    confirmBook,
    confirmMove,
    confirmStatus,
    dateRange,
    datetimeOnDay,
    emptyState,
    findFreeSlotAt,
    formatClock,
    formatDayHeader,
    formatRangeLabel,
    isInsideOpenPopover,
    minutesFromOffset,
    nowLineTop,
    parseIsoDate,
    positionStyle,
    reduceError,
    replacePaintedSlots,
    resolveScheduleId,
    revertBook,
    revertMove,
    revertPaint,
    revertStatus,
    snapRange,
    snapshotMove,
    snapshotStatus,
    stateFromGrid,
    timeBounds,
    toIsoDate,
    visibleDays
} from './emrEnhancedCalendarLogic';

const ANY_LOCATION = 'any';
const VIEW_DAY = 'day';
const VIEW_WEEK = 'week';

export default class EmrEnhancedCalendar extends NavigationMixin(LightningElement) {
    practitionerId;
    locationKey = ANY_LOCATION;
    locationOptions = [{ label: 'Any location', value: ANY_LOCATION }];
    schedules = [];
    viewMode = VIEW_WEEK;
    selectedDate;
    slotDurationMinutes = DEFAULT_DURATION;
    defaultScheduleId;
    hasMoreSlots = false;
    errorMessage;
    isLoading = false;
    isWorking = false;
    manageAvailability = false;
    hideFilters = false;
    hideManageAvailability = false;
    lockedPatientId;
    embedded = false;
    state = emptyState();

    bookingPopover;
    bookingPatientId;
    bookingType;
    bookingReason = '';
    actionPopover;

    drag;
    paint;
    tempPaintIds = [];

    viewOptions = [
        { label: 'Day', value: VIEW_DAY },
        { label: 'Week', value: VIEW_WEEK }
    ];
    typeOptions = [
        { label: 'Checkup', value: 'Checkup' },
        { label: 'Emergency', value: 'Emergency' },
        { label: 'Follow-up', value: 'Follow-up' },
        { label: 'Routine', value: 'Routine' },
        { label: 'Walk-in', value: 'Walk-in' }
    ];

    connectedCallback() {
        this.selectedDate = civilDateKey(new Date(), TIME_ZONE);
        this._onKeyDown = (event) => this.handleDocumentKey(event);
        this._onPointerDown = (event) => this.handleDocumentPointer(event);
        document.addEventListener('keydown', this._onKeyDown);
        document.addEventListener('pointerdown', this._onPointerDown);
    }

    disconnectedCallback() {
        document.removeEventListener('keydown', this._onKeyDown);
        document.removeEventListener('pointerdown', this._onPointerDown);
    }

    get patientObjectApiName() {
        return PATIENT_OBJECT.objectApiName;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
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
        return formatRangeLabel(this.selectedDate, this.isWeek, this.slotDurationMinutes);
    }

    get hasSlots() {
        return this.state.slots.length > 0;
    }

    get showEmptyFilter() {
        return !this.canLoadGrid && !this.isLoading;
    }

    get showEmptySlots() {
        return this.canLoadGrid && !this.isLoading && !this.hasSlots && !this.manageAvailability && !this.errorMessage;
    }

    get showGrid() {
        return this.canLoadGrid && (this.hasSlots || this.manageAvailability) && !this.showEmptyFilter;
    }

    get gridClass() {
        return this.isWeek ? 'grid grid_week' : 'grid grid_day';
    }

    get toolbarClass() {
        return this.hideFilters ? 'toolbar toolbar_nav-only' : 'toolbar';
    }

    get showFilters() {
        return !this.hideFilters;
    }

    get showManageAvailability() {
        return !this.hideManageAvailability;
    }

    get showBookingPatientPicker() {
        return !this.lockedPatientId;
    }

    get manageToggleLabel() {
        return this.manageAvailability ? 'Managing availability' : 'Manage availability';
    }

    /**
     * Opens the calendar for guided booking (used by emrAppointmentBooking).
     * Locks the chosen provider/location/date and optional patient.
     * @param {object} context practitionerId, locationKey, selectedDate, patientId
     */
    @api
    beginBooking(context) {
        if (!context) {
            return;
        }
        this.embedded = true;
        this.hideFilters = true;
        this.hideManageAvailability = true;
        this.manageAvailability = false;
        this.practitionerId = context.practitionerId;
        this.locationKey = context.locationKey || ANY_LOCATION;
        this.selectedDate = context.selectedDate || civilDateKey(new Date(), TIME_ZONE);
        this.viewMode = context.viewMode === VIEW_DAY ? VIEW_DAY : VIEW_WEEK;
        this.lockedPatientId = context.patientId;
        this.bookingPatientId = context.patientId;
        this.closePopovers();
        this.loadLocations();
        this.loadGrid();
    }

    get isBookDisabled() {
        return this.isBusy || !this.bookingPatientId || !this.bookingType || !this.bookingPopover?.slotId;
    }

    get selectedAction() {
        return this.actionPopover?.block;
    }

    get selectedActionTitle() {
        return this.selectedAction?.patientName || this.selectedAction?.name || 'Appointment';
    }

    get canArriveSelected() {
        return canArrive(this.selectedAction);
    }

    get canCancelSelected() {
        return canCancel(this.selectedAction);
    }

    get canNoShowSelected() {
        return canNoShow(this.selectedAction);
    }

    get canOpenChart() {
        return !!(this.selectedAction?.encounterId || this.selectedAction?.patientId);
    }

    get openChartLabel() {
        return this.selectedAction?.encounterId ? 'Open chart' : 'Open patient';
    }

    get timeLabels() {
        const bounds = timeBounds(this.state.slots, TIME_ZONE);
        return buildTimeRows(bounds.startMinutes, bounds.endMinutes, this.slotDurationMinutes).map((row) => ({
            key: String(row.minutes),
            label: row.label,
            className: row.label ? 'time-tick time-tick_label' : 'time-tick',
            style: `height:${ROW_HEIGHT}px`
        }));
    }

    get dayColumns() {
        const days = visibleDays(this.selectedDate, this.isWeek);
        const bounds = timeBounds(this.state.slots, TIME_ZONE);
        const totalHeight =
            buildTimeRows(bounds.startMinutes, bounds.endMinutes, this.slotDurationMinutes).length * ROW_HEIGHT;
        const today = new Date();
        const nowTop = nowLineTop(bounds.startMinutes, this.slotDurationMinutes, ROW_HEIGHT, today, TIME_ZONE);

        return days.map((day) => {
            const key = toIsoDate(day);
            const header = formatDayHeader(day);
            const isToday = civilDateKey(today, TIME_ZONE) === key;
            return {
                key,
                weekday: header.weekday,
                dateLabel: header.dateLabel,
                headerClass: isToday ? 'day-header day-header_today' : 'day-header',
                bodyStyle: `height:${totalHeight}px`,
                slots: this.slotsForDay(key, bounds.startMinutes),
                blocks: this.blocksForDay(key, bounds.startMinutes),
                showNow: isToday && nowTop != null && nowTop >= 0 && nowTop <= totalHeight,
                nowStyle: `top:${nowTop}px`,
                paintStyle: this.paintStyleForDay(key, bounds.startMinutes)
            };
        });
    }

    slotsForDay(dayKey, startMinutes) {
        return this.state.slots
            .filter((slot) => civilDateKey(slot.startTime, TIME_ZONE) === dayKey)
            .map((slot) => ({
                id: slot.id,
                title: `${slot.status} · ${formatClock(slot.startTime, TIME_ZONE)}–${formatClock(slot.endTime, TIME_ZONE)}`,
                className: slotClass(slot.status),
                style: positionStyle(
                    slot.startTime,
                    slot.endTime,
                    startMinutes,
                    this.slotDurationMinutes,
                    ROW_HEIGHT,
                    TIME_ZONE
                ),
                status: slot.status
            }));
    }

    blocksForDay(dayKey, startMinutes) {
        return this.state.blocks
            .filter((block) => civilDateKey(block.startTime, TIME_ZONE) === dayKey)
            .map((block) => {
                const dragging = this.drag?.appointmentId === block.id;
                return {
                    id: block.id,
                    slotId: block.slotId,
                    label: block.patientName || block.name || 'Appointment',
                    meta: `${formatClock(block.startTime, TIME_ZONE)} · ${block.status}`,
                    title: `${block.patientName || block.name || 'Appointment'} · ${block.status}`,
                    className: [
                        'block',
                        blockStatusClass(block.status),
                        canDragBlock(block) ? 'block_draggable' : '',
                        block.pending ? 'block_pending' : '',
                        dragging ? 'block_dragging' : ''
                    ]
                        .filter(Boolean)
                        .join(' '),
                    style: dragging
                        ? this.dragPreviewStyle(startMinutes)
                        : positionStyle(
                              block.startTime,
                              block.endTime,
                              startMinutes,
                              this.slotDurationMinutes,
                              ROW_HEIGHT,
                              TIME_ZONE
                          )
                };
            });
    }

    dragPreviewStyle(startMinutes) {
        if (!this.drag?.previewStart) {
            return '';
        }
        return `${positionStyle(
            this.drag.previewStart,
            this.drag.previewEnd,
            startMinutes,
            this.slotDurationMinutes,
            ROW_HEIGHT,
            TIME_ZONE
        )}left:2px;right:2px;`;
    }

    paintStyleForDay(dayKey, startMinutes) {
        if (!this.paint || this.paint.dayKey !== dayKey) {
            return null;
        }
        const snapped = snapRange(this.paint.startMinutes, this.paint.endMinutes, this.slotDurationMinutes);
        const day = parseIsoDate(dayKey);
        return positionStyle(
            datetimeOnDay(day, snapped.startMinutes, TIME_ZONE),
            datetimeOnDay(day, snapped.endMinutes, TIME_ZONE),
            startMinutes,
            this.slotDurationMinutes,
            ROW_HEIGHT,
            TIME_ZONE
        );
    }

    async handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
        this.errorMessage = undefined;
        this.closePopovers();
        await this.loadLocations();
        await this.loadGrid();
    }

    handleLocationChange(event) {
        this.locationKey = event.detail.value;
        this.errorMessage = undefined;
        this.closePopovers();
        this.loadGrid();
    }

    handleViewChange(event) {
        this.viewMode = event.detail.value;
        this.closePopovers();
        this.loadGrid();
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this.closePopovers();
        this.loadGrid();
    }

    handlePrev() {
        this.shiftDate(this.isWeek ? -7 : -1);
    }

    handleNext() {
        this.shiftDate(this.isWeek ? 7 : 1);
    }

    handleToday() {
        this.selectedDate = civilDateKey(new Date(), TIME_ZONE);
        this.closePopovers();
        this.loadGrid();
    }

    handleRefresh() {
        this.loadGrid();
    }

    handleManageToggle(event) {
        this.manageAvailability = event.detail.checked;
        this.closePopovers();
        this.paint = undefined;
    }

    shiftDate(days) {
        this.selectedDate = toIsoDate(addDays(parseIsoDate(this.selectedDate), days));
        this.closePopovers();
        this.loadGrid();
    }

    handleSlotClick(event) {
        event.stopPropagation();
        if (this.manageAvailability || this.drag) {
            return;
        }
        const slotId = event.currentTarget.dataset.slotId;
        const slot = this.state.slots.find((row) => row.id === slotId);
        if (!slot || slot.status !== SLOT_FREE) {
            return;
        }
        this.openBookingPopover(slot, event.currentTarget);
    }

    handleBlockPointerDown(event) {
        if (this.manageAvailability || (event.button != null && event.button !== 0)) {
            return;
        }
        const appointmentId = event.currentTarget.dataset.appointmentId;
        const block = this.state.blocks.find((row) => row.id === appointmentId);
        if (!canDragBlock(block)) {
            return;
        }
        event.stopPropagation();
        event.currentTarget.setPointerCapture(event.pointerId);
        this.drag = {
            appointmentId,
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            moved: false,
            snapshot: snapshotMove(this.state, appointmentId),
            previewStart: block.startTime,
            previewEnd: block.endTime,
            originDayKey: civilDateKey(block.startTime, TIME_ZONE)
        };
    }

    handleBlockPointerMove(event) {
        if (!this.drag || this.drag.pointerId !== event.pointerId) {
            return;
        }
        const dx = event.clientX - this.drag.startX;
        const dy = event.clientY - this.drag.startY;
        if (!this.drag.moved && Math.hypot(dx, dy) < DRAG_THRESHOLD) {
            return;
        }
        this.drag.moved = true;
        this.closePopovers();
        const hit = this.hitTest(event.clientX, event.clientY);
        if (hit) {
            const duration = minutesBetween(this.drag.snapshot.block.startTime, this.drag.snapshot.block.endTime);
            this.drag.previewStart = datetimeOnDay(parseIsoDate(hit.dayKey), hit.minutes, TIME_ZONE);
            this.drag.previewEnd = new Date(this.drag.previewStart.getTime() + duration * 60000);
            this.drag.previewDayKey = hit.dayKey;
        }
        this.state = { slots: this.state.slots, blocks: this.state.blocks };
    }

    async handleBlockPointerUp(event) {
        if (!this.drag || this.drag.pointerId !== event.pointerId) {
            return;
        }
        const drag = this.drag;
        this.drag = undefined;
        try {
            event.currentTarget.releasePointerCapture(event.pointerId);
        } catch (e) {
            // Capture may already be released.
        }
        if (!drag.moved) {
            const block = this.state.blocks.find((row) => row.id === drag.appointmentId);
            if (block) {
                this.openActionPopover(block, event.currentTarget);
            }
            return;
        }
        const hit = this.hitTest(event.clientX, event.clientY);
        const target = hit ? findFreeSlotAt(this.state.slots, hit.dayKey, hit.minutes, TIME_ZONE) : null;
        if (!target || target.id === drag.snapshot.fromSlotId) {
            this.state = revertMove(this.state, drag.snapshot);
            if (target?.id !== drag.snapshot.fromSlotId) {
                this.toast('Drop on a Free slot to reschedule.', 'error');
            }
            return;
        }
        await this.commitMove(drag, target);
    }

    handleDayPointerDown(event) {
        if (!this.manageAvailability || (event.button != null && event.button !== 0)) {
            return;
        }
        if (event.target.closest('.block')) {
            return;
        }
        const dayKey = event.currentTarget.dataset.dayKey;
        const bounds = timeBounds(this.state.slots, TIME_ZONE);
        const rect = event.currentTarget.getBoundingClientRect();
        const minutes = minutesFromOffset(
            event.clientY - rect.top,
            bounds.startMinutes,
            this.slotDurationMinutes,
            ROW_HEIGHT
        );
        this.paint = { dayKey, startMinutes: minutes, endMinutes: minutes + this.slotDurationMinutes };
        event.currentTarget.setPointerCapture(event.pointerId);
        this.closePopovers();
    }

    handleDayPointerMove(event) {
        if (!this.paint) {
            return;
        }
        const bounds = timeBounds(this.state.slots, TIME_ZONE);
        const rect = event.currentTarget.getBoundingClientRect();
        this.paint = {
            ...this.paint,
            endMinutes: minutesFromOffset(
                event.clientY - rect.top,
                bounds.startMinutes,
                this.slotDurationMinutes,
                ROW_HEIGHT
            )
        };
        this.state = { slots: this.state.slots, blocks: this.state.blocks };
    }

    async handleDayPointerUp(event) {
        if (!this.paint) {
            return;
        }
        const paint = this.paint;
        this.paint = undefined;
        try {
            event.currentTarget.releasePointerCapture(event.pointerId);
        } catch (e) {
            // Capture may already be released.
        }
        await this.commitPaint(paint);
    }

    handleBookingPatient(event) {
        this.bookingPatientId = event.detail.recordId;
    }

    handleBookingType(event) {
        this.bookingType = event.detail.value;
    }

    handleBookingReason(event) {
        this.bookingReason = event.detail.value;
    }

    handleCloseBooking() {
        this.bookingPopover = undefined;
        this.bookingPatientId = this.lockedPatientId;
        this.bookingType = undefined;
        this.bookingReason = '';
    }

    handleCloseActions() {
        this.actionPopover = undefined;
    }

    async handleBookSubmit() {
        if (this.isBookDisabled) {
            return;
        }
        const slotId = this.bookingPopover.slotId;
        const tempId = `temp-book-${Date.now()}`;
        const patientId = this.bookingPatientId;
        const appointmentType = this.bookingType;
        const reason = this.bookingReason;
        this.state = applyOptimisticBook(this.state, {
            slotId,
            tempId,
            patientId,
            patientName: 'New appointment',
            appointmentType,
            reason
        });
        this.handleCloseBooking();
        this.isWorking = true;
        try {
            const result = await bookAppointment({
                patientId,
                slotId,
                appointmentType,
                reason
            });
            if (result?.success === false) {
                this.state = revertBook(this.state, { tempId, slotId });
                this.toast(result.reason || 'This slot is no longer available.', 'error');
                return;
            }
            this.state = confirmBook(this.state, {
                tempId,
                appointmentId: result.appointmentId || result.appointment?.Id,
                appointmentName: result.appointmentName || result.appointment?.Name,
                appointmentStatus: result.appointmentStatus
            });
            this.toast(result.appointmentName || 'Appointment booked.', 'success');
            this.dispatchEvent(
                new CustomEvent('booked', {
                    bubbles: true,
                    composed: true,
                    detail: {
                        appointmentId: result.appointmentId,
                        appointmentName: result.appointmentName,
                        slotId: result.slotId || slotId,
                        status: result.appointmentStatus
                    }
                })
            );
        } catch (error) {
            this.state = revertBook(this.state, { tempId, slotId });
            this.toast(reduceError(error), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    async handleArrive() {
        await this.runBlockAction(
            (block) => applyOptimisticStatus(this.state, { appointmentId: block.id, status: APPT_ARRIVED }),
            (block) => arriveAppointment({ appointmentId: block.id }),
            (block, result) =>
                confirmStatus(this.state, {
                    appointmentId: block.id,
                    status: result.appointmentStatus || APPT_ARRIVED,
                    encounterId: result.encounterId,
                    encounterName: result.encounterName
                }),
            'Patient arrived'
        );
    }

    async handleCancelAppointment() {
        await this.runBlockAction(
            (block) =>
                applyOptimisticStatus(this.state, {
                    appointmentId: block.id,
                    status: APPT_CANCELLED,
                    slotStatus: SLOT_FREE
                }),
            (block) => cancelAppointment({ appointmentId: block.id }),
            (block, result) =>
                confirmStatus(this.state, {
                    appointmentId: block.id,
                    status: result.appointmentStatus || APPT_CANCELLED
                }),
            'Appointment cancelled'
        );
    }

    async handleNoShow() {
        await this.runBlockAction(
            (block) => applyOptimisticStatus(this.state, { appointmentId: block.id, status: APPT_NO_SHOW }),
            (block) => markNoShow({ appointmentId: block.id }),
            (block, result) =>
                confirmStatus(this.state, {
                    appointmentId: block.id,
                    status: result.appointmentStatus || APPT_NO_SHOW
                }),
            'Marked no show'
        );
    }

    handleOpenChart() {
        const block = this.selectedAction;
        if (!block) {
            return;
        }
        const recordId = block.encounterId || block.patientId;
        const objectApiName = block.encounterId
            ? ENCOUNTER_OBJECT.objectApiName
            : PATIENT_OBJECT.objectApiName;
        this.handleCloseActions();
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate](recordViewPageRef(recordId, objectApiName));
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
            this.errorMessage = reduceError(error);
        }
    }

    async loadGrid() {
        if (!this.canLoadGrid || !this.selectedDate) {
            this.state = emptyState();
            this.hasMoreSlots = false;
            return;
        }
        const range = dateRange(this.selectedDate, this.isWeek);
        this.isLoading = true;
        this.errorMessage = undefined;
        this.closePopovers();
        try {
            const locationName = this.locationKey === ANY_LOCATION ? null : this.locationKey;
            const [view, schedules] = await Promise.all([
                getGrid({
                    practitionerId: this.practitionerId || null,
                    locationName,
                    rangeStart: range.start,
                    rangeEnd: range.end
                }),
                getActiveSchedules({
                    practitionerId: this.practitionerId || null,
                    locationName
                })
            ]);
            this.state = stateFromGrid(view?.slots || []);
            this.hasMoreSlots = !!view?.hasMore;
            this.schedules = schedules || [];
            this.defaultScheduleId = view?.defaultScheduleId || this.schedules[0]?.id;
            this.slotDurationMinutes =
                (view?.slots && view.slots.length ? view.slotDurationMinutes : this.schedules[0]?.slotDurationMinutes) ||
                DEFAULT_DURATION;
        } catch (error) {
            this.state = emptyState();
            this.hasMoreSlots = false;
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async commitMove(drag, target) {
        const snapshot = {
            ...drag.snapshot,
            toSlotId: target.id,
            toSlotStatus: target.status
        };
        this.state = applyOptimisticMove(this.state, {
            appointmentId: drag.appointmentId,
            toSlotId: target.id
        });
        this.isWorking = true;
        try {
            const result = await rescheduleAppointment({
                appointmentId: drag.appointmentId,
                newSlotId: target.id
            });
            if (result?.success === false) {
                this.state = revertMove(this.state, snapshot);
                this.toast(result.reason || 'This slot is no longer available.', 'error');
                return;
            }
            this.state = confirmMove(this.state, drag.appointmentId);
            this.toast('Appointment rescheduled.', 'success');
        } catch (error) {
            this.state = revertMove(this.state, snapshot);
            this.toast(reduceError(error), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    async commitPaint(paint) {
        const scheduleId = resolveScheduleId(
            this.schedules,
            this.state.slots,
            this.locationKey === ANY_LOCATION ? null : this.locationKey
        ) || this.defaultScheduleId;
        if (!scheduleId) {
            this.toast('Create a schedule for this provider before painting availability.', 'error');
            return;
        }
        const snapped = snapRange(paint.startMinutes, paint.endMinutes, this.slotDurationMinutes);
        const day = parseIsoDate(paint.dayKey);
        const startTime = datetimeOnDay(day, snapped.startMinutes, TIME_ZONE);
        const endTime = datetimeOnDay(day, snapped.endMinutes, TIME_ZONE);
        const tempId = `temp-slot-${Date.now()}`;
        this.tempPaintIds = [tempId];
        this.state = applyOptimisticPaint(this.state, [
            {
                id: tempId,
                startTime,
                endTime,
                status: SLOT_FREE,
                scheduleId
            }
        ]);
        this.isWorking = true;
        try {
            const result = await createAdHocSlots({
                scheduleId,
                ranges: [{ startTime, endTime }]
            });
            if (result?.success === false) {
                this.state = revertPaint(this.state, this.tempPaintIds);
                this.toast(result.reason || 'Unable to create slots.', 'error');
                return;
            }
            const created = (result.slots || []).map((row) => ({
                id: row.Id,
                startTime: row.Start__c,
                endTime: row.End__c,
                status: row.Status__c || SLOT_FREE,
                scheduleId: row.Schedule__c || scheduleId
            }));
            this.state = replacePaintedSlots(this.state, this.tempPaintIds, created);
            if (result.created === 0) {
                this.toast('That range overlaps existing slots.', 'info');
            }
        } catch (error) {
            this.state = revertPaint(this.state, this.tempPaintIds);
            this.toast(reduceError(error), 'error');
        } finally {
            this.tempPaintIds = [];
            this.isWorking = false;
        }
    }

    async runBlockAction(applyOptimistic, callAction, applyConfirm, successTitle) {
        const block = this.selectedAction;
        if (!block) {
            return;
        }
        const snapshot = snapshotStatus(this.state, block.id);
        this.state = applyOptimistic(block);
        this.handleCloseActions();
        this.isWorking = true;
        try {
            const result = await callAction(block);
            if (result?.success === false) {
                this.state = revertStatus(this.state, snapshot);
                this.toast(result.reason || 'Unable to update the appointment.', 'error');
                return;
            }
            this.state = applyConfirm(block, result || {});
            this.toast(result?.appointmentName || successTitle, 'success');
        } catch (error) {
            this.state = revertStatus(this.state, snapshot);
            this.toast(reduceError(error), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    openBookingPopover(slot, anchor) {
        this.actionPopover = undefined;
        this.bookingPatientId = undefined;
        this.bookingType = undefined;
        this.bookingReason = '';
        this.bookingPopover = {
            slotId: slot.id,
            when: `${formatClock(slot.startTime, TIME_ZONE)} – ${formatClock(slot.endTime, TIME_ZONE)}`,
            style: popoverStyle(anchor, this.template.querySelector('.calendar-shell'))
        };
    }

    openActionPopover(block, anchor) {
        this.bookingPopover = undefined;
        this.actionPopover = {
            block: { ...block },
            when: `${formatClock(block.startTime, TIME_ZONE)} – ${formatClock(block.endTime, TIME_ZONE)}`,
            style: popoverStyle(anchor, this.template.querySelector('.calendar-shell'))
        };
    }

    closePopovers() {
        this.bookingPopover = undefined;
        this.actionPopover = undefined;
        this.bookingPatientId = this.lockedPatientId;
        this.bookingType = undefined;
        this.bookingReason = '';
    }

    handleDocumentKey(event) {
        if (event.key === 'Escape') {
            this.closePopovers();
            this.paint = undefined;
            if (this.drag?.snapshot) {
                this.state = revertMove(this.state, this.drag.snapshot);
            }
            this.drag = undefined;
        }
    }

    handlePopoverPointerDown(event) {
        event.stopPropagation();
    }

    handleDocumentPointer(event) {
        if (!this.bookingPopover && !this.actionPopover) {
            return;
        }
        const popovers = [...this.template.querySelectorAll('.popover')];
        if (isInsideOpenPopover(event, popovers)) {
            return;
        }
        this.closePopovers();
    }

    hitTest(clientX, clientY) {
        const bodies = this.template.querySelectorAll('.day-body');
        for (const body of bodies) {
            const rect = body.getBoundingClientRect();
            if (clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom) {
                const bounds = timeBounds(this.state.slots, TIME_ZONE);
                return {
                    dayKey: body.dataset.dayKey,
                    minutes: minutesFromOffset(
                        clientY - rect.top,
                        bounds.startMinutes,
                        this.slotDurationMinutes,
                        ROW_HEIGHT
                    )
                };
            }
        }
        return null;
    }

    toast(message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: variant === 'success' ? 'Calendar updated' : variant === 'info' ? 'Availability' : 'Calendar',
                message,
                variant: variant === 'info' ? 'info' : variant
            })
        );
    }
}

function slotClass(status) {
    if (status === SLOT_FREE) {
        return 'slot slot_free';
    }
    if (status === SLOT_BLOCKED) {
        return 'slot slot_blocked';
    }
    return 'slot slot_busy';
}

function blockStatusClass(status) {
    if (status === APPT_ARRIVED) {
        return 'block_arrived';
    }
    if (status === APPT_NO_SHOW) {
        return 'block_noshow';
    }
    if (status === APPT_CANCELLED) {
        return 'block_cancelled';
    }
    if (status === 'Fulfilled') {
        return 'block_fulfilled';
    }
    return 'block_booked';
}

function minutesBetween(start, end) {
    return Math.max((new Date(end).getTime() - new Date(start).getTime()) / 60000, DEFAULT_DURATION);
}

function popoverStyle(anchor, shell) {
    if (!anchor || !shell) {
        return 'top:4.5rem;left:1rem;';
    }
    const shellRect = shell.getBoundingClientRect();
    const rect = anchor.getBoundingClientRect();
    const top = Math.max(8, rect.bottom - shellRect.top + 6);
    const left = Math.max(8, rect.left - shellRect.left);
    return `top:${top}px;left:${left}px;`;
}
