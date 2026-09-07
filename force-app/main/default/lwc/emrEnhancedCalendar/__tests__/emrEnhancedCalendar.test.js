import {
    APPT_ARRIVED,
    APPT_BOOKED,
    SLOT_BUSY,
    SLOT_FREE,
    applyOptimisticBook,
    applyOptimisticMove,
    applyOptimisticPaint,
    confirmBook,
    confirmMove,
    civilDateKey,
    datetimeOnDay,
    findFreeSlotAt,
    formatClock,
    isInsideOpenPopover,
    minutesOfDay,
    positionStyle,
    revertBook,
    revertMove,
    revertPaint,
    snapshotMove,
    stateFromGrid,
    timeBounds
} from '../emrEnhancedCalendarLogic';

function at(hours, minutes) {
    return new Date(2026, 8, 8, hours, minutes, 0, 0);
}

function sampleGrid() {
    return [
        {
            id: 'slot-old',
            startTime: at(9, 0),
            endTime: at(9, 20),
            status: SLOT_BUSY,
            scheduleId: 'sched-1',
            appointment: {
                id: 'appt-1',
                name: 'Ada Lopez - 9:00 AM',
                status: APPT_BOOKED,
                patientId: 'pat-1',
                patientName: 'Ada Lopez',
                appointmentType: 'Checkup'
            }
        },
        {
            id: 'slot-free',
            startTime: at(9, 20),
            endTime: at(9, 40),
            status: SLOT_FREE,
            scheduleId: 'sched-1'
        }
    ];
}

describe('emrEnhancedCalendar optimistic client logic', () => {
    describe('reschedule move and snap-back', () => {
        it('moves the block to the target slot immediately', () => {
            const original = stateFromGrid(sampleGrid());
            const snapshot = snapshotMove(original, 'appt-1');
            const moved = applyOptimisticMove(original, {
                appointmentId: 'appt-1',
                toSlotId: 'slot-free'
            });

            const block = moved.blocks.find((row) => row.id === 'appt-1');
            const oldSlot = moved.slots.find((row) => row.id === 'slot-old');
            const newSlot = moved.slots.find((row) => row.id === 'slot-free');

            expect(snapshot.fromSlotId).toBe('slot-old');
            expect(block.slotId).toBe('slot-free');
            expect(block.startTime).toEqual(at(9, 20));
            expect(block.endTime).toEqual(at(9, 40));
            expect(block.pending).toBe(true);
            expect(oldSlot.status).toBe(SLOT_FREE);
            expect(newSlot.status).toBe(SLOT_BUSY);
        });

        it('snaps the block back when the server rejects the move', () => {
            const original = stateFromGrid(sampleGrid());
            const snapshot = {
                ...snapshotMove(original, 'appt-1'),
                toSlotId: 'slot-free',
                toSlotStatus: SLOT_FREE
            };
            const moved = applyOptimisticMove(original, {
                appointmentId: 'appt-1',
                toSlotId: 'slot-free'
            });
            const snapped = revertMove(moved, snapshot);

            const block = snapped.blocks.find((row) => row.id === 'appt-1');
            const oldSlot = snapped.slots.find((row) => row.id === 'slot-old');
            const newSlot = snapped.slots.find((row) => row.id === 'slot-free');

            expect(block.slotId).toBe('slot-old');
            expect(block.startTime).toBe(original.blocks[0].startTime);
            expect(block.endTime).toBe(original.blocks[0].endTime);
            expect(block.pending).toBe(false);
            expect(oldSlot.status).toBe(SLOT_BUSY);
            expect(newSlot.status).toBe(SLOT_FREE);
            expect(newSlot.id).not.toBe(block.slotId);
        });

        it('keeps the moved block after a successful confirm', () => {
            const original = stateFromGrid(sampleGrid());
            const moved = applyOptimisticMove(original, {
                appointmentId: 'appt-1',
                toSlotId: 'slot-free'
            });
            const confirmed = confirmMove(moved, 'appt-1');
            const block = confirmed.blocks.find((row) => row.id === 'appt-1');

            expect(block.slotId).toBe('slot-free');
            expect(block.pending).toBe(false);
            expect(confirmed.slots.find((row) => row.id === 'slot-old').status).toBe(SLOT_FREE);
            expect(confirmed.slots.find((row) => row.id === 'slot-free').status).toBe(SLOT_BUSY);
        });
    });

    describe('booking add and remove', () => {
        it('optimistically adds a booked block and busies the slot', () => {
            const original = stateFromGrid(sampleGrid());
            const booked = applyOptimisticBook(original, {
                slotId: 'slot-free',
                tempId: 'temp-book-1',
                patientId: 'pat-2',
                patientName: 'Ben Ng',
                appointmentType: 'Follow-up',
                reason: 'Sore throat'
            });
            const block = booked.blocks.find((row) => row.id === 'temp-book-1');
            const slot = booked.slots.find((row) => row.id === 'slot-free');

            expect(booked.blocks).toHaveLength(2);
            expect(block.status).toBe(APPT_BOOKED);
            expect(block.temporary).toBe(true);
            expect(block.pending).toBe(true);
            expect(block.patientName).toBe('Ben Ng');
            expect(slot.status).toBe(SLOT_BUSY);
        });

        it('removes the optimistic block and frees the slot on failure', () => {
            const original = stateFromGrid(sampleGrid());
            const booked = applyOptimisticBook(original, {
                slotId: 'slot-free',
                tempId: 'temp-book-1',
                patientId: 'pat-2',
                patientName: 'Ben Ng',
                appointmentType: 'Follow-up'
            });
            const reverted = revertBook(booked, { tempId: 'temp-book-1', slotId: 'slot-free' });

            expect(reverted.blocks.find((row) => row.id === 'temp-book-1')).toBeUndefined();
            expect(reverted.blocks).toHaveLength(1);
            expect(reverted.slots.find((row) => row.id === 'slot-free').status).toBe(SLOT_FREE);
            expect(reverted.slots.find((row) => row.id === 'slot-old').status).toBe(SLOT_BUSY);
        });

        it('replaces the temporary id when the server confirms the book', () => {
            const original = stateFromGrid(sampleGrid());
            const booked = applyOptimisticBook(original, {
                slotId: 'slot-free',
                tempId: 'temp-book-1',
                patientId: 'pat-2',
                patientName: 'Ben Ng',
                appointmentType: 'Follow-up'
            });
            const confirmed = confirmBook(booked, {
                tempId: 'temp-book-1',
                appointmentId: 'appt-2',
                appointmentName: 'Ben Ng - 9:20 AM',
                appointmentStatus: APPT_ARRIVED
            });
            const block = confirmed.blocks.find((row) => row.id === 'appt-2');

            expect(confirmed.blocks.find((row) => row.id === 'temp-book-1')).toBeUndefined();
            expect(block.name).toBe('Ben Ng - 9:20 AM');
            expect(block.status).toBe(APPT_ARRIVED);
            expect(block.pending).toBe(false);
            expect(block.temporary).toBe(false);
            expect(confirmed.slots.find((row) => row.id === 'slot-free').status).toBe(SLOT_BUSY);
        });
    });

    describe('slot targeting and painted availability', () => {
        it('finds the Free slot covering a dropped time', () => {
            const { slots } = stateFromGrid(sampleGrid());
            const hit = findFreeSlotAt(slots, '2026-09-08', 9 * 60 + 25);
            const miss = findFreeSlotAt(slots, '2026-09-08', 9 * 60 + 5);

            expect(hit?.id).toBe('slot-free');
            expect(miss).toBeUndefined();
        });

        it('adds painted Free slots and can roll them back', () => {
            const original = stateFromGrid(sampleGrid());
            const painted = applyOptimisticPaint(original, [
                {
                    id: 'temp-slot-1',
                    startTime: at(10, 0),
                    endTime: at(10, 20),
                    status: SLOT_FREE,
                    scheduleId: 'sched-1'
                }
            ]);
            expect(painted.slots).toHaveLength(3);
            expect(painted.slots.find((row) => row.id === 'temp-slot-1').status).toBe(SLOT_FREE);

            const reverted = revertPaint(painted, ['temp-slot-1']);
            expect(reverted.slots).toHaveLength(2);
            expect(reverted.slots.find((row) => row.id === 'temp-slot-1')).toBeUndefined();
        });
    });

    describe('booking popover click-outside', () => {
        it('keeps the popover open when the click is inside a nested input', () => {
            const popover = { classList: { contains: (name) => name === 'popover' } };
            const input = { tagName: 'INPUT', parentNode: popover, classList: { contains: () => false } };
            const event = { target: input, composedPath: () => [input] };

            expect(isInsideOpenPopover(event, [popover])).toBe(true);
        });

        it('keeps the popover open for a portaled listbox overlay', () => {
            const option = {
                tagName: 'SPAN',
                getAttribute: (name) => (name === 'role' ? 'option' : null),
                classList: { contains: () => false }
            };
            const event = { target: option, composedPath: () => [option, document.body] };

            expect(isInsideOpenPopover(event, [])).toBe(true);
        });

        it('closes when the click is outside the popover and overlays', () => {
            const page = {
                tagName: 'DIV',
                classList: { contains: () => false },
                getAttribute: () => null
            };
            const event = { target: page, composedPath: () => [page] };

            expect(isInsideOpenPopover(event, [{ classList: { contains: () => false } }])).toBe(false);
        });
    });

    describe('org timezone clock', () => {
        const mayaUtc = '2026-09-02T16:00:00.000Z';
        const mayaEndUtc = '2026-09-02T16:20:00.000Z';
        const pacific = 'America/Los_Angeles';

        it('reads 9:00 AM Pacific from the seeded UTC instant', () => {
            expect(minutesOfDay(mayaUtc, pacific)).toBe(9 * 60);
            expect(civilDateKey(mayaUtc, pacific)).toBe('2026-09-02');
            expect(formatClock(mayaUtc, pacific)).toMatch(/9:00/);
        });

        it('does not label the same instant as 12:00 PM when the org is Pacific', () => {
            expect(minutesOfDay(mayaUtc, 'America/New_York')).toBe(12 * 60);
            expect(formatClock(mayaUtc, pacific)).not.toMatch(/12:00/);
        });

        it('positions a 9:00 AM Pacific appointment on the 9:00 row', () => {
            expect(positionStyle(mayaUtc, mayaEndUtc, 8 * 60, 20, 28, pacific)).toContain('top:84px');
        });

        it('converts a Pacific civil time back to the original UTC instant', () => {
            const instant = datetimeOnDay(new Date(2026, 8, 2), 9 * 60, pacific);
            expect(instant.toISOString()).toBe(mayaUtc);
        });

        it('finds a Free slot using org-zone minutes instead of the browser clock', () => {
            const slots = [
                {
                    id: 'slot-maya',
                    startTime: mayaUtc,
                    endTime: mayaEndUtc,
                    status: SLOT_FREE
                }
            ];
            const bounds = timeBounds(slots, pacific);

            expect(bounds.startMinutes).toBe(9 * 60);
            expect(findFreeSlotAt(slots, '2026-09-02', 9 * 60 + 5, pacific)?.id).toBe('slot-maya');
            expect(findFreeSlotAt(slots, '2026-09-02', 12 * 60 + 5, pacific)).toBeUndefined();
        });
    });
});
