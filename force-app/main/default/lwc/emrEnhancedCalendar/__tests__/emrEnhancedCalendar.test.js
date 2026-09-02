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
    findFreeSlotAt,
    revertBook,
    revertMove,
    revertPaint,
    snapshotMove,
    stateFromGrid
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
});
