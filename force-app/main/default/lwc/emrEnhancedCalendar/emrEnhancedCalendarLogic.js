export const SLOT_FREE = 'Free';
export const SLOT_BUSY = 'Busy';
export const SLOT_BLOCKED = 'Blocked';
export const APPT_BOOKED = 'Booked';
export const APPT_ARRIVED = 'Arrived';
export const APPT_CANCELLED = 'Cancelled';
export const APPT_NO_SHOW = 'No Show';
export const APPT_PROPOSED = 'Proposed';
export const DEFAULT_DURATION = 30;
export const DEFAULT_START_MINUTES = 8 * 60;
export const DEFAULT_END_MINUTES = 17 * 60;
export const ROW_HEIGHT = 28;
export const DRAG_THRESHOLD = 4;
export const OPEN_STATUSES = new Set([APPT_PROPOSED, APPT_BOOKED]);

export function emptyState() {
    return { slots: [], blocks: [] };
}

export function cloneState(state) {
    const source = state || emptyState();
    return {
        slots: (source.slots || []).map((slot) => ({ ...slot })),
        blocks: (source.blocks || []).map((block) => ({ ...block }))
    };
}

export function stateFromGrid(slots) {
    const normalized = (slots || []).map(normalizeSlot);
    const blocks = [];
    normalized.forEach((slot) => {
        if (slot.appointment) {
            blocks.push(blockFromSlot(slot));
        }
    });
    return { slots: normalized, blocks };
}

export function normalizeSlot(slot) {
    return {
        id: slot.id,
        startTime: slot.startTime,
        endTime: slot.endTime,
        status: slot.status || SLOT_FREE,
        appointmentType: slot.appointmentType,
        locationName: slot.locationName,
        practitionerId: slot.practitionerId,
        practitionerName: slot.practitionerName,
        scheduleId: slot.scheduleId,
        durationMinutes: slot.durationMinutes,
        appointment: slot.appointment ? { ...slot.appointment } : null
    };
}

export function blockFromSlot(slot) {
    const appointment = slot.appointment || {};
    return {
        id: appointment.id,
        name: appointment.name,
        slotId: slot.id,
        startTime: slot.startTime,
        endTime: slot.endTime,
        status: appointment.status || APPT_BOOKED,
        appointmentType: appointment.appointmentType || slot.appointmentType,
        reason: appointment.reason,
        patientId: appointment.patientId,
        patientName: appointment.patientName,
        encounterId: appointment.encounterId,
        encounterName: appointment.encounterName,
        practitionerId: slot.practitionerId,
        practitionerName: slot.practitionerName,
        locationName: slot.locationName,
        pending: false,
        temporary: false
    };
}

export function slotFromApex(row) {
    return normalizeSlot({
        id: row.Id || row.id,
        startTime: row.Start__c || row.startTime,
        endTime: row.End__c || row.endTime,
        status: row.Status__c || row.status || SLOT_FREE,
        scheduleId: row.Schedule__c || row.scheduleId,
        locationName: row.locationName,
        practitionerId: row.practitionerId,
        practitionerName: row.practitionerName,
        appointmentType: row.Appointment_Type__c || row.appointmentType
    });
}

export function applyOptimisticBook(state, payload) {
    const next = cloneState(state);
    const slot = next.slots.find((row) => row.id === payload.slotId);
    if (!slot) {
        return next;
    }
    slot.status = SLOT_BUSY;
    next.blocks.push({
        id: payload.tempId,
        name: payload.patientName || 'New appointment',
        slotId: slot.id,
        startTime: slot.startTime,
        endTime: slot.endTime,
        status: APPT_BOOKED,
        appointmentType: payload.appointmentType,
        reason: payload.reason,
        patientId: payload.patientId,
        patientName: payload.patientName,
        encounterId: null,
        encounterName: null,
        practitionerId: slot.practitionerId,
        practitionerName: slot.practitionerName,
        locationName: slot.locationName,
        pending: true,
        temporary: true
    });
    return next;
}

export function confirmBook(state, payload) {
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === payload.tempId);
    if (block) {
        block.id = payload.appointmentId || block.id;
        block.name = payload.appointmentName || block.name;
        block.status = payload.appointmentStatus || APPT_BOOKED;
        block.pending = false;
        block.temporary = false;
    }
    return next;
}

export function revertBook(state, payload) {
    const next = cloneState(state);
    next.blocks = next.blocks.filter((row) => row.id !== payload.tempId);
    const slot = next.slots.find((row) => row.id === payload.slotId);
    if (slot) {
        slot.status = SLOT_FREE;
        slot.appointment = null;
    }
    return next;
}

export function snapshotMove(state, appointmentId) {
    const block = (state.blocks || []).find((row) => row.id === appointmentId);
    if (!block) {
        return null;
    }
    return {
        appointmentId,
        block: { ...block },
        fromSlotId: block.slotId,
        fromSlotStatus: slotStatus(state, block.slotId)
    };
}

export function applyOptimisticMove(state, payload) {
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === payload.appointmentId);
    const target = next.slots.find((row) => row.id === payload.toSlotId);
    if (!block || !target) {
        return next;
    }
    const fromSlot = next.slots.find((row) => row.id === block.slotId);
    if (fromSlot) {
        fromSlot.status = SLOT_FREE;
        fromSlot.appointment = null;
    }
    target.status = SLOT_BUSY;
    block.slotId = target.id;
    block.startTime = target.startTime;
    block.endTime = target.endTime;
    block.practitionerId = target.practitionerId;
    block.practitionerName = target.practitionerName;
    block.locationName = target.locationName;
    block.pending = true;
    return next;
}

export function revertMove(state, snapshot) {
    if (!snapshot) {
        return cloneState(state);
    }
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === snapshot.appointmentId);
    const movedSlotId = block ? block.slotId : snapshot.toSlotId;
    if (movedSlotId && movedSlotId !== snapshot.fromSlotId) {
        const movedSlot = next.slots.find((row) => row.id === movedSlotId);
        if (movedSlot) {
            movedSlot.status = snapshot.toSlotStatus || SLOT_FREE;
            movedSlot.appointment = null;
        }
    }
    const original = next.slots.find((row) => row.id === snapshot.fromSlotId);
    if (original) {
        original.status = snapshot.fromSlotStatus || SLOT_BUSY;
    }
    if (block) {
        Object.assign(block, snapshot.block, { pending: false });
    }
    return next;
}

export function confirmMove(state, appointmentId) {
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === appointmentId);
    if (block) {
        block.pending = false;
    }
    return next;
}

export function snapshotStatus(state, appointmentId) {
    const block = (state.blocks || []).find((row) => row.id === appointmentId);
    if (!block) {
        return null;
    }
    return {
        appointmentId,
        block: { ...block },
        slotStatus: slotStatus(state, block.slotId)
    };
}

export function applyOptimisticStatus(state, payload) {
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === payload.appointmentId);
    if (!block) {
        return next;
    }
    block.status = payload.status;
    block.pending = true;
    if (payload.encounterId) {
        block.encounterId = payload.encounterId;
        block.encounterName = payload.encounterName;
    }
    const slot = next.slots.find((row) => row.id === block.slotId);
    if (slot && payload.slotStatus) {
        slot.status = payload.slotStatus;
    }
    return next;
}

export function confirmStatus(state, payload) {
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === payload.appointmentId);
    if (block) {
        block.pending = false;
        if (payload.status) {
            block.status = payload.status;
        }
        if (payload.encounterId) {
            block.encounterId = payload.encounterId;
            block.encounterName = payload.encounterName;
        }
    }
    return next;
}

export function revertStatus(state, snapshot) {
    if (!snapshot) {
        return cloneState(state);
    }
    const next = cloneState(state);
    const block = next.blocks.find((row) => row.id === snapshot.appointmentId);
    if (block) {
        Object.assign(block, snapshot.block, { pending: false });
    }
    const slot = next.slots.find((row) => row.id === snapshot.block.slotId);
    if (slot) {
        slot.status = snapshot.slotStatus;
    }
    return next;
}

export function applyOptimisticPaint(state, slots) {
    const next = cloneState(state);
    (slots || []).forEach((slot) => {
        if (!next.slots.some((row) => row.id === slot.id)) {
            next.slots.push(normalizeSlot(slot));
        }
    });
    return next;
}

export function revertPaint(state, slotIds) {
    const remove = new Set(slotIds || []);
    const next = cloneState(state);
    next.slots = next.slots.filter((row) => !remove.has(row.id));
    return next;
}

export function replacePaintedSlots(state, tempIds, createdSlots) {
    const next = revertPaint(state, tempIds);
    return applyOptimisticPaint(next, createdSlots);
}

export function findFreeSlotAt(slots, dayKey, minutes, timeZone) {
    return (slots || []).find((slot) => {
        if (slot.status !== SLOT_FREE) {
            return false;
        }
        if (civilDateKey(slot.startTime, timeZone) !== dayKey) {
            return false;
        }
        const start = minutesOfDay(slot.startTime, timeZone);
        const end = minutesOfDay(slot.endTime, timeZone);
        return minutes >= start && minutes < end;
    });
}

export function findSlotById(slots, slotId) {
    return (slots || []).find((slot) => slot.id === slotId);
}

export function assignLanes(items) {
    const sorted = [...(items || [])].sort((left, right) => {
        const startDelta = new Date(left.startTime).getTime() - new Date(right.startTime).getTime();
        if (startDelta !== 0) {
            return startDelta;
        }
        return String(left.id || '').localeCompare(String(right.id || ''));
    });
    const laneEnds = [];
    const lanes = new Map();
    sorted.forEach((item) => {
        const start = new Date(item.startTime).getTime();
        let lane = laneEnds.findIndex((end) => end <= start);
        if (lane === -1) {
            lane = laneEnds.length;
            laneEnds.push(0);
        }
        laneEnds[lane] = new Date(item.endTime).getTime();
        lanes.set(item.id, lane);
    });
    return { lanes, laneCount: Math.max(1, laneEnds.length) };
}

export function laneInsetStyle(lane, laneCount) {
    const lanes = Math.max(1, laneCount || 1);
    const widthPct = 100 / lanes;
    const index = lane || 0;
    return `left:calc(${index * widthPct}% + 2px);width:calc(${widthPct}% - 4px);right:auto;`;
}

export function canDragBlock(block) {
    return !!(block && OPEN_STATUSES.has(block.status) && !block.pending);
}

export function canArrive(block) {
    return !!(block && OPEN_STATUSES.has(block.status) && !block.encounterId);
}

export function canCancel(block) {
    return !!(block && (OPEN_STATUSES.has(block.status) || block.status === APPT_ARRIVED));
}

export function canNoShow(block) {
    return !!(block && OPEN_STATUSES.has(block.status));
}

export function resolveScheduleId(schedules, slots, locationKey) {
    const fromSlots = (slots || []).find((slot) => slot.scheduleId)?.scheduleId;
    if (fromSlots) {
        return fromSlots;
    }
    const rows = schedules || [];
    if (locationKey) {
        const match = rows.find((row) => row.locationName === locationKey);
        if (match) {
            return match.id;
        }
    }
    return rows.length ? rows[0].id : null;
}

export function timeBounds(slots, timeZone) {
    if (!slots || !slots.length) {
        return { startMinutes: DEFAULT_START_MINUTES, endMinutes: DEFAULT_END_MINUTES };
    }
    let minStart = Number.POSITIVE_INFINITY;
    let maxEnd = 0;
    slots.forEach((slot) => {
        minStart = Math.min(minStart, minutesOfDay(slot.startTime, timeZone));
        maxEnd = Math.max(maxEnd, minutesOfDay(slot.endTime, timeZone));
    });
    return {
        startMinutes: Math.floor(minStart / 60) * 60,
        endMinutes: Math.max(Math.ceil(maxEnd / 60) * 60, Math.floor(minStart / 60) * 60 + 60)
    };
}

export function buildTimeRows(startMinutes, endMinutes, rowMinutes) {
    const increment = rowMinutes > 0 ? rowMinutes : DEFAULT_DURATION;
    const rows = [];
    for (let minutes = startMinutes; minutes < endMinutes; minutes += increment) {
        const minuteOfHour = minutes % 60;
        rows.push({
            minutes,
            label: minuteOfHour === 0 || minuteOfHour === 30 ? formatMinutes(minutes) : ''
        });
    }
    return rows;
}

export function minutesFromOffset(offsetY, startMinutes, rowMinutes, rowHeight) {
    const height = rowHeight || ROW_HEIGHT;
    const increment = rowMinutes > 0 ? rowMinutes : DEFAULT_DURATION;
    const rows = Math.max(0, Math.floor(offsetY / height));
    return startMinutes + rows * increment;
}

export function snapRange(startMinutes, endMinutes, rowMinutes) {
    const increment = rowMinutes > 0 ? rowMinutes : DEFAULT_DURATION;
    const low = Math.min(startMinutes, endMinutes);
    const high = Math.max(startMinutes, endMinutes);
    const snappedStart = Math.floor(low / increment) * increment;
    let snappedEnd = Math.ceil(high / increment) * increment;
    if (snappedEnd <= snappedStart) {
        snappedEnd = snappedStart + increment;
    }
    return { startMinutes: snappedStart, endMinutes: snappedEnd };
}

export function datetimeOnDay(day, minutes, timeZone) {
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    if (!timeZone) {
        return new Date(day.getFullYear(), day.getMonth(), day.getDate(), hours, mins, 0, 0);
    }
    return civilTimeToUtc(day.getFullYear(), day.getMonth(), day.getDate(), hours, mins, timeZone);
}

export function minutesOfDay(value, timeZone) {
    const date = new Date(value);
    if (!timeZone) {
        return date.getHours() * 60 + date.getMinutes();
    }
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23'
    }).formatToParts(date);
    const hour = Number(parts.find((part) => part.type === 'hour')?.value || 0);
    const minute = Number(parts.find((part) => part.type === 'minute')?.value || 0);
    return hour * 60 + minute;
}

export function startOfWeek(date) {
    const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const day = copy.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    copy.setDate(copy.getDate() + offset);
    return copy;
}

export function addDays(date, days) {
    const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    copy.setDate(copy.getDate() + days);
    return copy;
}

export function parseIsoDate(value) {
    const [year, month, day] = value.split('-').map((part) => Number(part));
    return new Date(year, month - 1, day);
}

export function toIsoDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

export function civilDateKey(value, timeZone) {
    const date = value instanceof Date ? value : new Date(value);
    if (!timeZone) {
        return toIsoDate(date);
    }
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    }).formatToParts(date);
    const year = parts.find((part) => part.type === 'year')?.value;
    const month = parts.find((part) => part.type === 'month')?.value;
    const day = parts.find((part) => part.type === 'day')?.value;
    return `${year}-${month}-${day}`;
}

export function isSameDay(left, right) {
    return (
        left.getFullYear() === right.getFullYear() &&
        left.getMonth() === right.getMonth() &&
        left.getDate() === right.getDate()
    );
}

export function formatMinutes(totalMinutes) {
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    const date = new Date();
    date.setHours(hours, minutes, 0, 0);
    return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

export function formatClock(value, timeZone) {
    if (!value) {
        return '';
    }
    const options = { hour: 'numeric', minute: '2-digit' };
    if (timeZone) {
        options.timeZone = timeZone;
    }
    return new Date(value).toLocaleTimeString(undefined, options);
}

export function formatDayHeader(date) {
    return {
        weekday: date.toLocaleDateString(undefined, { weekday: 'short' }),
        dateLabel: String(date.getDate())
    };
}

export function formatRangeLabel(selectedDate, isWeek, durationMinutes) {
    if (!selectedDate) {
        return '';
    }
    const duration = durationMinutes ? ` · ${durationMinutes}-minute slots` : '';
    const selected = parseIsoDate(selectedDate);
    if (isWeek) {
        const start = startOfWeek(selected);
        const end = addDays(start, 6);
        return `${formatShortDate(start)} – ${formatShortDate(end)}${duration}`;
    }
    return `${formatLongDate(selected)}${duration}`;
}

export function visibleDays(selectedDate, isWeek) {
    const selected = parseIsoDate(selectedDate);
    if (!isWeek) {
        return [selected];
    }
    const start = startOfWeek(selected);
    return [0, 1, 2, 3, 4, 5, 6].map((offset) => addDays(start, offset));
}

export function dateRange(selectedDate, isWeek) {
    const selected = parseIsoDate(selectedDate);
    if (isWeek) {
        const start = startOfWeek(selected);
        return { start: toIsoDate(start), end: toIsoDate(addDays(start, 6)) };
    }
    const iso = toIsoDate(selected);
    return { start: iso, end: iso };
}

export function nowLineTop(startMinutes, rowMinutes, rowHeight, now, timeZone) {
    const current = now || new Date();
    const minutes = minutesOfDay(current, timeZone);
    if (minutes < startMinutes) {
        return null;
    }
    const increment = rowMinutes > 0 ? rowMinutes : DEFAULT_DURATION;
    const height = rowHeight || ROW_HEIGHT;
    return ((minutes - startMinutes) / increment) * height;
}

export function positionStyle(startTime, endTime, startMinutes, rowMinutes, rowHeight, timeZone) {
    const increment = rowMinutes > 0 ? rowMinutes : DEFAULT_DURATION;
    const height = rowHeight || ROW_HEIGHT;
    const start = minutesOfDay(startTime, timeZone);
    const end = minutesOfDay(endTime, timeZone);
    const duration = Math.max(end - start, increment);
    const top = ((start - startMinutes) / increment) * height;
    const blockHeight = Math.max((duration / increment) * height - 2, 18);
    return `top:${top}px;height:${blockHeight}px;`;
}

const OVERLAY_TAGS = new Set([
    'LIGHTNING-PRIMITIVE-COMBOBOX-DROPDOWN',
    'LIGHTNING-LOOKUP-DESKTOP',
    'LIGHTNING-OVERLAY',
    'LIGHTNING-DIALOG',
    'LIGHTNING-MODAL',
    'LIGHTNING-PICKLIST-DROPDOWN'
]);

/**
 * True when a document-level pointer event landed in an open booking/action
 * popover or a portaled picker/combobox overlay (shadow DOM + body portal).
 */
export function isInsideOpenPopover(event, popoverNodes) {
    const popovers = (popoverNodes || []).filter(Boolean);
    const nodes = collectEventNodes(event);
    for (const node of nodes) {
        if (popovers.includes(node) || hasClass(node, 'popover')) {
            return true;
        }
        if (isPortaledPickerOverlay(node)) {
            return true;
        }
    }
    return false;
}

export function collectEventNodes(event) {
    const seen = new Set();
    const nodes = [];
    const add = (node) => {
        if (!node || seen.has(node)) {
            return;
        }
        seen.add(node);
        nodes.push(node);
    };
    if (event && typeof event.composedPath === 'function') {
        event.composedPath().forEach(add);
    }
    let current = event ? event.target : null;
    while (current) {
        add(current);
        if (current.assignedSlot) {
            current = current.assignedSlot;
            continue;
        }
        if (current.parentNode) {
            current = current.parentNode;
            continue;
        }
        if (current.host) {
            current = current.host;
            continue;
        }
        break;
    }
    return nodes;
}

function hasClass(node, className) {
    return !!(node && node.classList && node.classList.contains(className));
}

function isPortaledPickerOverlay(node) {
    if (!node) {
        return false;
    }
    const tag = (node.tagName || '').toUpperCase();
    if (OVERLAY_TAGS.has(tag)) {
        return true;
    }
    if (typeof node.getAttribute === 'function') {
        const role = node.getAttribute('role');
        if (role === 'listbox' || role === 'option' || role === 'listitem') {
            return true;
        }
    }
    return (
        hasClass(node, 'slds-listbox') ||
        hasClass(node, 'slds-dropdown') ||
        hasClass(node, 'slds-combobox__dropdown') ||
        hasClass(node, 'slds-lookup') ||
        hasClass(node, 'slds-popover') ||
        hasClass(node, 'slds-modal')
    );
}

export function reduceError(error) {
    if (error?.body?.message) {
        return error.body.message;
    }
    if (Array.isArray(error?.body)) {
        return error.body.map((item) => item.message).join(', ');
    }
    return error?.message || error?.reason || 'Unable to update the calendar.';
}

function civilTimeToUtc(year, monthIndex, day, hours, minutes, timeZone) {
    const utcGuess = Date.UTC(year, monthIndex, day, hours, minutes, 0);
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23'
    }).formatToParts(new Date(utcGuess));
    const read = (type) => Number(parts.find((part) => part.type === type)?.value || 0);
    const actual = Date.UTC(read('year'), read('month') - 1, read('day'), read('hour'), read('minute'));
    const desired = Date.UTC(year, monthIndex, day, hours, minutes);
    return new Date(utcGuess + (desired - actual));
}

function slotStatus(state, slotId) {
    const slot = (state.slots || []).find((row) => row.id === slotId);
    return slot ? slot.status : null;
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
