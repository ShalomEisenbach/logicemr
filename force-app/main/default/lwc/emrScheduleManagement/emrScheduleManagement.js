import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSchedules from '@salesforce/apex/ScheduleManagementController.getSchedules';
import saveSchedule from '@salesforce/apex/ScheduleManagementController.saveSchedule';
import previewSlots from '@salesforce/apex/ScheduleManagementController.previewSlots';
import generateSlots from '@salesforce/apex/ScheduleManagementController.generateSlots';
import getSlots from '@salesforce/apex/ScheduleManagementController.getSlots';
import toggleSlotStatus from '@salesforce/apex/ScheduleManagementController.toggleSlotStatus';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import SCHEDULE_OBJECT from '@salesforce/schema/Schedule__c';

const NEW_SCHEDULE = 'new';

export default class EmrScheduleManagement extends LightningElement {
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

    rangeStart;
    rangeEnd;
    dailyStart = '09:00';
    dailyEnd = '17:00';
    selectedDays = ['1', '2', '3', '4', '5'];

    preview;
    slots = [];
    hasMoreSlots = false;

    errorMessage;
    isLoading = false;
    isSaving = false;
    isGenerating = false;
    isToggling = false;

    dayOptions = [
        { label: 'Sunday', value: '0' },
        { label: 'Monday', value: '1' },
        { label: 'Tuesday', value: '2' },
        { label: 'Wednesday', value: '3' },
        { label: 'Thursday', value: '4' },
        { label: 'Friday', value: '5' },
        { label: 'Saturday', value: '6' }
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
        { label: 'Status', fieldName: 'status', type: 'text' },
        {
            type: 'button',
            typeAttributes: {
                label: { fieldName: 'toggleLabel' },
                name: 'toggle',
                disabled: { fieldName: 'toggleDisabled' },
                variant: 'neutral'
            }
        }
    ];

    connectedCallback() {
        const today = new Date();
        this.rangeStart = toIsoDate(today);
        this.rangeEnd = toIsoDate(addDays(today, 6));
        this.planningHorizonStart = this.rangeStart;
        this.planningHorizonEnd = this.rangeEnd;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
    }

    get scheduleObjectApiName() {
        return SCHEDULE_OBJECT.objectApiName;
    }

    get isBusy() {
        return this.isLoading || this.isSaving || this.isGenerating || this.isToggling;
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

    get hasSelectedSchedule() {
        return !!this.selectedScheduleId;
    }

    get saveLabel() {
        return this.selectedScheduleId ? 'Save schedule' : 'Create schedule';
    }

    get isSaveDisabled() {
        return this.isBusy || !this.practitionerId;
    }

    get isGenerateDisabled() {
        return (
            this.isBusy ||
            !this.selectedScheduleId ||
            !this.preview ||
            this.preview.overLimit ||
            this.preview.slotCount === 0
        );
    }

    get isPreviewDisabled() {
        return this.isBusy || !this.selectedScheduleId;
    }

    get hasPreview() {
        return this.preview != null;
    }

    get previewSummary() {
        if (!this.preview) {
            return '';
        }
        if (this.preview.overLimit) {
            return `${this.preview.slotCount} slots would be created. Narrow the range, window, or interval before generating.`;
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
        return `${this.preview.slotCount} slot(s) will be created.${skipped}`;
    }

    get hasSlots() {
        return this.slots && this.slots.length > 0;
    }

    get showSlotsEmpty() {
        return this.hasSelectedSchedule && !this.hasSlots && !this.isLoading;
    }

    get slotRows() {
        return (this.slots || []).map((row) => ({
            id: row.id,
            startTime: row.startTime,
            endTime: row.endTime,
            status: row.status,
            toggleLabel: row.status === 'Blocked' ? 'Free' : 'Block',
            toggleDisabled: !row.canToggle || this.isBusy
        }));
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
            this.slots = [];
            this.hasMoreSlots = false;
        }
    }

    handleScheduleSelect(event) {
        this.selectedScheduleKey = event.detail.value;
        this.errorMessage = undefined;
        this.clearPreview();
        if (this.selectedScheduleKey === NEW_SCHEDULE) {
            this.resetScheduleForm(false);
            this.slots = [];
            this.hasMoreSlots = false;
            return;
        }
        const selected = (this.schedules || []).find((row) => row.id === this.selectedScheduleKey);
        if (selected) {
            this.applySchedule(selected);
            this.loadSlots();
        }
    }

    handleLocationChange(event) {
        this.locationName = event.detail.value;
        this.clearPreview();
    }

    handleDurationChange(event) {
        this.slotDurationMinutes = event.detail.value;
        this.clearPreview();
    }

    handleHorizonStartChange(event) {
        this.planningHorizonStart = event.detail.value;
        if (!this.rangeStart) {
            this.rangeStart = this.planningHorizonStart;
        }
        this.clearPreview();
    }

    handleHorizonEndChange(event) {
        this.planningHorizonEnd = event.detail.value;
        if (!this.rangeEnd) {
            this.rangeEnd = this.planningHorizonEnd;
        }
        this.clearPreview();
    }

    handleActiveChange(event) {
        this.active = event.detail.checked;
    }

    handleRangeStartChange(event) {
        this.rangeStart = event.detail.value;
        this.clearPreview();
    }

    handleRangeEndChange(event) {
        this.rangeEnd = event.detail.value;
        this.clearPreview();
    }

    handleDailyStartChange(event) {
        this.dailyStart = event.detail.value;
        this.clearPreview();
    }

    handleDailyEndChange(event) {
        this.dailyEnd = event.detail.value;
        this.clearPreview();
    }

    handleDaysChange(event) {
        this.selectedDays = event.detail.value;
        this.clearPreview();
    }

    async handleSaveSchedule() {
        if (this.isSaveDisabled) {
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
                active: this.active
            });
            this.applySchedule(saved);
            await this.loadSchedules(saved.id);
            this.toast('Schedule saved', `${saved.name} is ready for slot generation.`, 'success');
            if (!this.rangeStart && saved.planningHorizonStart) {
                this.rangeStart = saved.planningHorizonStart;
            }
            if (!this.rangeEnd && saved.planningHorizonEnd) {
                this.rangeEnd = saved.planningHorizonEnd;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handlePreview() {
        if (this.isPreviewDisabled) {
            return;
        }
        this.isGenerating = true;
        this.errorMessage = undefined;
        try {
            this.preview = await previewSlots(this.generationRequest());
        } catch (error) {
            this.preview = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isGenerating = false;
        }
    }

    async handleGenerate() {
        if (this.isGenerateDisabled) {
            return;
        }
        this.isGenerating = true;
        this.errorMessage = undefined;
        try {
            const result = await generateSlots(this.generationRequest());
            this.toast(
                'Slots created',
                `Created ${result.created} slot(s). ${result.skippedExisting} existing slot(s) skipped.`,
                'success'
            );
            this.clearPreview();
            await this.loadSlots();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isGenerating = false;
        }
    }

    async handleSlotRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action?.name !== 'toggle' || !row?.id || this.isToggling) {
            return;
        }
        this.isToggling = true;
        this.errorMessage = undefined;
        try {
            const updated = await toggleSlotStatus({ slotId: row.id });
            this.slots = (this.slots || []).map((slot) => (slot.id === updated.id ? updated : slot));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isToggling = false;
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
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadSlots() {
        if (!this.selectedScheduleId || !this.rangeStart || !this.rangeEnd) {
            this.slots = [];
            this.hasMoreSlots = false;
            return;
        }
        this.isLoading = true;
        try {
            const view = await getSlots({
                scheduleId: this.selectedScheduleId,
                rangeStart: this.rangeStart,
                rangeEnd: this.rangeEnd
            });
            this.slots = view?.slots || [];
            this.hasMoreSlots = !!view?.hasMore;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
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
        if (row.planningHorizonStart) {
            this.rangeStart = row.planningHorizonStart;
        }
        if (row.planningHorizonEnd) {
            this.rangeEnd = row.planningHorizonEnd;
        }
    }

    resetScheduleForm(resetDates) {
        this.selectedScheduleId = undefined;
        this.selectedScheduleKey = NEW_SCHEDULE;
        this.scheduleName = undefined;
        this.locationName = '';
        this.slotDurationMinutes = 20;
        this.active = true;
        if (resetDates) {
            const today = new Date();
            this.planningHorizonStart = toIsoDate(today);
            this.planningHorizonEnd = toIsoDate(addDays(today, 6));
            this.rangeStart = this.planningHorizonStart;
            this.rangeEnd = this.planningHorizonEnd;
        }
    }

    generationRequest() {
        return {
            scheduleId: this.selectedScheduleId,
            rangeStart: this.rangeStart,
            rangeEnd: this.rangeEnd,
            dailyStart: this.dailyStart,
            dailyEnd: this.dailyEnd,
            includedDays: (this.selectedDays || []).map((value) => parseInt(value, 10))
        };
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
