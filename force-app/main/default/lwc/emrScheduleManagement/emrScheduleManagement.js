import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSchedules from '@salesforce/apex/ScheduleManagementController.getSchedules';
import saveSchedule from '@salesforce/apex/ScheduleManagementController.saveSchedule';
import previewSlots from '@salesforce/apex/ScheduleManagementController.previewSlots';
import generateSlots from '@salesforce/apex/ScheduleManagementController.generateSlots';
import getSlotSummary from '@salesforce/apex/ScheduleManagementController.getSlotSummary';
import getUnavailabilities from '@salesforce/apex/ScheduleManagementController.getUnavailabilities';
import applyUnavailability from '@salesforce/apex/ScheduleManagementController.applyUnavailability';
import removeUnavailability from '@salesforce/apex/ScheduleManagementController.removeUnavailability';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import SCHEDULE_OBJECT from '@salesforce/schema/Schedule__c';

const NEW_SCHEDULE = 'new';
const DAY_DEFS = [
    { label: 'Sunday', value: '0' },
    { label: 'Monday', value: '1' },
    { label: 'Tuesday', value: '2' },
    { label: 'Wednesday', value: '3' },
    { label: 'Thursday', value: '4' },
    { label: 'Friday', value: '5' },
    { label: 'Saturday', value: '6' }
];

export default class EmrScheduleManagement extends LightningElement {
    @api recordId;
    practitionerId;
    schedules = [];
    selectedScheduleKey = NEW_SCHEDULE;
    selectedScheduleId;
    scheduleName;
    locationName = '';
    slotDurationMinutes = 20;
    planningHorizonStart;
    planningHorizonEnd;
    active = true;
    hoursByDay = defaultHoursByDay();

    preview;
    summary;
    unavailabilities = [];

    timeOffStartDate;
    timeOffEndDate;
    timeOffStartTime = '09:00';
    timeOffEndTime = '17:00';
    timeOffAllDay = true;
    timeOffReason = '';
    thisScheduleOnly = true;

    errorMessage;
    isLoading = false;
    isSaving = false;
    isGenerating = false;
    isApplyingTimeOff = false;
    _windowSeq = 0;
    _previewTimer;

    connectedCallback() {
        const today = new Date();
        this.planningHorizonStart = toIsoDate(today);
        this.planningHorizonEnd = toIsoDate(addDays(today, 27));
        this.timeOffStartDate = toIsoDate(today);
        this.timeOffEndDate = toIsoDate(today);
        if (this.recordId) {
            this.practitionerId = this.recordId;
            this.loadSchedules();
        }
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    get scheduleObjectApiName() {
        return SCHEDULE_OBJECT.objectApiName;
    }

    get isBusy() {
        return this.isLoading || this.isSaving || this.isGenerating || this.isApplyingTimeOff;
    }

    get scheduleOptions() {
        const options = [{ label: 'New schedule', value: NEW_SCHEDULE }];
        (this.schedules || []).forEach((row) => {
            const location = row.locationName ? ` · ${row.locationName}` : '';
            const duration = row.slotDurationMinutes != null ? ` · ${row.slotDurationMinutes} min` : '';
            options.push({
                label: `${row.name || 'Schedule'}${location}${duration}`,
                value: row.id
            });
        });
        return options;
    }

    get hasExistingSchedules() {
        return this.schedules && this.schedules.length > 0;
    }

    get isPractitionerRecordPage() {
        return !!this.recordId;
    }

    get hasSelectedSchedule() {
        return !!this.selectedScheduleId;
    }

    get saveGenerateLabel() {
        return this.selectedScheduleId ? 'Save and generate' : 'Create and generate';
    }

    get isSaveGenerateDisabled() {
        return this.isBusy || !this.practitionerId || !this.planningHorizonStart || !this.planningHorizonEnd;
    }

    get dayRows() {
        return DAY_DEFS.map((day) => ({
            key: day.value,
            label: day.label,
            value: day.value,
            windows: (this.hoursByDay[day.value] || []).map((window) => ({ ...window }))
        }));
    }

    get hasPreview() {
        return this.preview != null;
    }

    get previewSummary() {
        if (!this.preview) {
            return '';
        }
        if (this.preview.overLimit) {
            return `${this.preview.slotCount} slots would be created. Narrow the horizon or increase slot duration before generating.`;
        }
        if (this.preview.slotCount === 0) {
            const skipped = this.preview.skippedExisting
                ? ` ${this.preview.skippedExisting} existing slot(s) were skipped.`
                : '';
            return `No new slots to create.${skipped}`;
        }
        const skipped = this.preview.skippedExisting
            ? ` ${this.preview.skippedExisting} existing slot(s) will be skipped.`
            : '';
        const blocked =
            this.preview.blockedCount > 0 ? ` ${this.preview.blockedCount} will be Blocked by time off.` : '';
        return `${this.preview.slotCount} slot(s) will be created (${this.preview.freeCount || 0} Free).${blocked}${skipped}`;
    }

    get showTimeOffTimes() {
        return !this.timeOffAllDay;
    }

    get isTimeOffDisabled() {
        return (
            this.isBusy ||
            !this.selectedScheduleId ||
            !this.practitionerId ||
            !this.timeOffStartDate ||
            !this.timeOffEndDate
        );
    }

    get hasUnavailabilities() {
        return this.unavailabilities && this.unavailabilities.length > 0;
    }

    get unavailabilityRows() {
        return (this.unavailabilities || []).map((row) => ({
            id: row.id,
            reason: row.reason,
            when: formatUnavailabilityRange(row)
        }));
    }

    get hasSummary() {
        return this.summary && this.summary.totalCount > 0;
    }

    get summaryText() {
        if (!this.summary) {
            return '';
        }
        return `${this.summary.totalCount} slot(s) in the planning horizon: ${this.summary.freeCount} Free, ${this.summary.blockedCount} Blocked, ${this.summary.busyCount} Busy.`;
    }

    handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
        this.errorMessage = undefined;
        this.clearPreview();
        this.resetScheduleForm(true);
        if (this.practitionerId) {
            this.loadSchedules();
        } else {
            this.schedules = [];
            this.summary = undefined;
            this.unavailabilities = [];
        }
    }

    handleScheduleSelect(event) {
        this.selectedScheduleKey = event.detail.value;
        this.errorMessage = undefined;
        this.clearPreview();
        if (this.selectedScheduleKey === NEW_SCHEDULE) {
            this.resetScheduleForm(false);
            this.summary = undefined;
            this.unavailabilities = [];
            return;
        }
        const selected = (this.schedules || []).find((row) => row.id === this.selectedScheduleKey);
        if (selected) {
            this.applySchedule(selected);
            this.loadSummary();
            this.loadUnavailabilities();
            this.schedulePreview();
        }
    }

    handleLocationChange(event) {
        this.locationName = event.detail.value;
    }

    handleDurationChange(event) {
        this.slotDurationMinutes = event.detail.value;
        this.schedulePreview();
    }

    handleHorizonStartChange(event) {
        this.planningHorizonStart = event.detail.value;
        this.schedulePreview();
    }

    handleHorizonEndChange(event) {
        this.planningHorizonEnd = event.detail.value;
        this.schedulePreview();
    }

    handleActiveChange(event) {
        this.active = event.detail.checked;
    }

    handleAddWindow(event) {
        const day = event.currentTarget.dataset.day;
        const windows = [...(this.hoursByDay[day] || [])];
        windows.push(this.newWindow('09:00', '17:00'));
        this.hoursByDay = { ...this.hoursByDay, [day]: windows };
        this.schedulePreview();
    }

    handleRemoveWindow(event) {
        const day = event.currentTarget.dataset.day;
        const windowId = event.currentTarget.dataset.windowId;
        const windows = (this.hoursByDay[day] || []).filter((row) => row.id !== windowId);
        this.hoursByDay = { ...this.hoursByDay, [day]: windows };
        this.schedulePreview();
    }

    handleWindowChange(event) {
        const day = event.currentTarget.dataset.day;
        const windowId = event.currentTarget.dataset.windowId;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        const windows = (this.hoursByDay[day] || []).map((row) =>
            row.id === windowId ? { ...row, [field]: value } : row
        );
        this.hoursByDay = { ...this.hoursByDay, [day]: windows };
        this.schedulePreview();
    }

    handleCopyWeekdays() {
        const monday = this.hoursByDay['1'] || [];
        const template = monday.length
            ? monday.map((row) => this.newWindow(row.startTime, row.endTime))
            : [this.newWindow('09:00', '17:00')];
        const next = { ...this.hoursByDay };
        ['1', '2', '3', '4', '5'].forEach((day) => {
            next[day] = template.map((row) => this.newWindow(row.startTime, row.endTime));
        });
        this.hoursByDay = next;
        this.schedulePreview();
        this.toast('Weekdays updated', 'Monday–Friday now use the same hours.', 'success');
    }

    handleTimeOffStartDateChange(event) {
        this.timeOffStartDate = event.detail.value;
    }

    handleTimeOffEndDateChange(event) {
        this.timeOffEndDate = event.detail.value;
    }

    handleTimeOffStartTimeChange(event) {
        this.timeOffStartTime = event.detail.value;
    }

    handleTimeOffEndTimeChange(event) {
        this.timeOffEndTime = event.detail.value;
    }

    handleTimeOffAllDayChange(event) {
        this.timeOffAllDay = event.detail.checked;
    }

    handleTimeOffReasonChange(event) {
        this.timeOffReason = event.detail.value;
    }

    handleThisScheduleOnlyChange(event) {
        this.thisScheduleOnly = event.detail.checked;
    }

    async handleSaveAndGenerate() {
        if (this.isSaveGenerateDisabled) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const saved = await saveSchedule({
                scheduleId: this.selectedScheduleId || null,
                practitionerId: this.practitionerId,
                locationName: this.locationName,
                slotDurationMinutes: this.toNumber(this.slotDurationMinutes),
                planningHorizonStart: this.planningHorizonStart || null,
                planningHorizonEnd: this.planningHorizonEnd || null,
                active: this.active,
                hours: this.collectHours()
            });
            this.applySchedule(saved);
            await this.loadSchedules(saved.id);

            this.isSaving = false;
            this.isGenerating = true;
            this.preview = await previewSlots({
                scheduleId: saved.id,
                rangeStart: this.planningHorizonStart,
                rangeEnd: this.planningHorizonEnd,
                hours: null
            });
            if (this.preview.overLimit) {
                this.toast('Preview over limit', this.previewSummary, 'error');
                return;
            }
            const result = await generateSlots({
                scheduleId: saved.id,
                rangeStart: this.planningHorizonStart,
                rangeEnd: this.planningHorizonEnd
            });
            this.toast(
                'Schedule ready',
                `Saved hours and created ${result.created} slot(s). ${result.skippedExisting} existing skipped.`,
                'success'
            );
            this.clearPreview();
            await this.loadSummary();
            await this.loadUnavailabilities();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
            this.isGenerating = false;
        }
    }

    async handleApplyTimeOff() {
        if (this.isTimeOffDisabled) {
            return;
        }
        this.isApplyingTimeOff = true;
        this.errorMessage = undefined;
        try {
            const startTime = this.buildTimeOffDatetime(this.timeOffStartDate, this.timeOffStartTime, false);
            const endTime = this.buildTimeOffDatetime(this.timeOffEndDate, this.timeOffEndTime, true);
            const result = await applyUnavailability({
                unavailabilityId: null,
                practitionerId: this.practitionerId,
                scheduleId: this.selectedScheduleId,
                startTime,
                endTime,
                allDay: this.timeOffAllDay,
                reason: this.timeOffReason,
                thisScheduleOnly: this.thisScheduleOnly
            });
            const conflictNote =
                result.bookedConflicts > 0
                    ? ` ${result.bookedConflicts} booked appointment(s) remain and were not changed.`
                    : '';
            this.toast(
                'Time off applied',
                `Blocked ${result.slotsBlocked} slot(s), created ${result.slotsCreated} blocked slot(s).${conflictNote}`,
                result.bookedConflicts > 0 ? 'warning' : 'success'
            );
            await this.loadUnavailabilities();
            await this.loadSummary();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isApplyingTimeOff = false;
        }
    }

    async handleRemoveTimeOff(event) {
        const id = event.currentTarget.dataset.id;
        if (!id || this.isBusy) {
            return;
        }
        this.isApplyingTimeOff = true;
        this.errorMessage = undefined;
        try {
            await removeUnavailability({ unavailabilityId: id });
            this.toast('Time off removed', 'Matching blocked slots were freed.', 'success');
            await this.loadUnavailabilities();
            await this.loadSummary();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isApplyingTimeOff = false;
        }
    }

    async loadSchedules(selectId) {
        if (!this.practitionerId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.schedules = (await getSchedules({ practitionerId: this.practitionerId })) || [];
            const keepId = selectId || this.selectedScheduleId;
            const match = keepId ? this.schedules.find((row) => row.id === keepId) : undefined;
            if (match) {
                this.applySchedule(match);
                await this.loadSummary();
                await this.loadUnavailabilities();
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadSummary() {
        if (!this.selectedScheduleId || !this.planningHorizonStart || !this.planningHorizonEnd) {
            this.summary = undefined;
            return;
        }
        try {
            this.summary = await getSlotSummary({
                scheduleId: this.selectedScheduleId,
                rangeStart: this.planningHorizonStart,
                rangeEnd: this.planningHorizonEnd
            });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    async loadUnavailabilities() {
        if (!this.practitionerId) {
            this.unavailabilities = [];
            return;
        }
        try {
            this.unavailabilities =
                (await getUnavailabilities({
                    practitionerId: this.practitionerId,
                    scheduleId: this.selectedScheduleId || null
                })) || [];
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    schedulePreview() {
        if (this._previewTimer) {
            clearTimeout(this._previewTimer);
        }
        this._previewTimer = setTimeout(() => this.refreshPreview(), 350);
    }

    async refreshPreview() {
        if (!this.selectedScheduleId || !this.planningHorizonStart || !this.planningHorizonEnd) {
            this.preview = undefined;
            return;
        }
        try {
            this.preview = await previewSlots({
                scheduleId: this.selectedScheduleId,
                rangeStart: this.planningHorizonStart,
                rangeEnd: this.planningHorizonEnd,
                hours: this.collectHours()
            });
        } catch (error) {
            this.preview = undefined;
            // Live preview should not block editing when hours are incomplete.
            if (this.collectHours().length) {
                this.errorMessage = this.reduceError(error);
            }
        }
    }

    applySchedule(row) {
        this.selectedScheduleId = row.id;
        this.selectedScheduleKey = row.id;
        this.scheduleName = row.name;
        this.locationName = row.locationName || '';
        this.slotDurationMinutes = row.slotDurationMinutes != null ? row.slotDurationMinutes : 20;
        this.planningHorizonStart = row.planningHorizonStart;
        this.planningHorizonEnd = row.planningHorizonEnd;
        this.active = row.active !== false;
        this.hoursByDay = hoursFromViews(row.hours, () => this.nextWindowId());
    }

    resetScheduleForm(resetDates) {
        this.selectedScheduleId = undefined;
        this.selectedScheduleKey = NEW_SCHEDULE;
        this.scheduleName = undefined;
        this.locationName = '';
        this.slotDurationMinutes = 20;
        this.active = true;
        this.hoursByDay = defaultHoursByDay(() => this.nextWindowId());
        if (resetDates) {
            const today = new Date();
            this.planningHorizonStart = toIsoDate(today);
            this.planningHorizonEnd = toIsoDate(addDays(today, 27));
        }
    }

    collectHours() {
        const hours = [];
        DAY_DEFS.forEach((day) => {
            (this.hoursByDay[day.value] || []).forEach((window) => {
                if (window.startTime && window.endTime) {
                    hours.push({
                        dayOfWeek: day.value,
                        startTime: normalizeTimeValue(window.startTime),
                        endTime: normalizeTimeValue(window.endTime)
                    });
                }
            });
        });
        return hours;
    }

    newWindow(startTime, endTime) {
        return {
            id: this.nextWindowId(),
            startTime: startTime || '09:00',
            endTime: endTime || '17:00'
        };
    }

    nextWindowId() {
        this._windowSeq += 1;
        return `w-${this._windowSeq}`;
    }

    buildTimeOffDatetime(dateValue, timeValue, isEnd) {
        const [year, month, day] = dateValue.split('-').map((part) => Number(part));
        let hours = 0;
        let minutes = 0;
        if (this.timeOffAllDay) {
            hours = isEnd ? 23 : 0;
            minutes = isEnd ? 59 : 0;
        } else {
            const normalized = normalizeTimeValue(timeValue) || (isEnd ? '17:00' : '09:00');
            const parts = normalized.split(':');
            hours = Number(parts[0]) || 0;
            minutes = Number(parts[1]) || 0;
        }
        return new Date(year, month - 1, day, hours, minutes, 0, 0).toISOString();
    }

    clearPreview() {
        this.preview = undefined;
    }

    toNumber(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        const parsed = Number(value);
        return Number.isNaN(parsed) ? null : parsed;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to update the schedule.';
    }
}

function defaultHoursByDay(idFactory) {
    const makeId = idFactory || (() => `seed-${Math.random().toString(36).slice(2, 8)}`);
    const result = {
        '0': [],
        '1': [],
        '2': [],
        '3': [],
        '4': [],
        '5': [],
        '6': []
    };
    ['1', '2', '3', '4', '5'].forEach((day) => {
        result[day] = [{ id: makeId(), startTime: '09:00', endTime: '17:00' }];
    });
    return result;
}

function hoursFromViews(hours, idFactory) {
    const result = defaultHoursByDay(idFactory);
    Object.keys(result).forEach((day) => {
        result[day] = [];
    });
    (hours || []).forEach((row) => {
        const day = String(row.dayOfWeek);
        if (!result[day]) {
            result[day] = [];
        }
        result[day].push({
            id: idFactory(),
            startTime: normalizeTimeValue(row.startTime) || '09:00',
            endTime: normalizeTimeValue(row.endTime) || '17:00'
        });
    });
    const hasAny = Object.values(result).some((windows) => windows.length);
    return hasAny ? result : defaultHoursByDay(idFactory);
}

function normalizeTimeValue(value) {
    if (!value) {
        return value;
    }
    const trimmed = String(value).trim();
    if (trimmed.length >= 5) {
        return trimmed.substring(0, 5);
    }
    return trimmed;
}

function formatUnavailabilityRange(row) {
    if (!row?.startTime || !row?.endTime) {
        return '';
    }
    const start = new Date(row.startTime);
    const end = new Date(row.endTime);
    const dateOpts = { month: 'short', day: 'numeric', year: 'numeric' };
    if (row.allDay) {
        return `${start.toLocaleDateString(undefined, dateOpts)} – ${end.toLocaleDateString(undefined, dateOpts)} (all day)`;
    }
    const timeOpts = { hour: 'numeric', minute: '2-digit' };
    return `${start.toLocaleString(undefined, { ...dateOpts, ...timeOpts })} – ${end.toLocaleString(undefined, {
        ...dateOpts,
        ...timeOpts
    })}`;
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
