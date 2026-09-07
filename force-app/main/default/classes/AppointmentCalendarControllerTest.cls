@IsTest
private class AppointmentCalendarControllerTest {
    private static final Date SLOT_DAY = Date.newInstance(2026, 9, 8);
    private static final String TYPE_CHECKUP = 'Checkup';
    private static final String TYPE_EMERGENCY = 'Emergency';

    @IsTest
    static void rescheduleFreesOldSlotAndBusiesNewSlot() {
        Patient__c patient = insertPatient('MRN-CAL-RS');
        Practitioner__c practitioner = insertPractitioner('Ada', 'Lopez');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic A');
        Datetime firstStart = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Slot__c oldSlot = insertSlot(schedule.Id, firstStart, firstStart.addMinutes(20), 'Busy');
        Slot__c newSlot = insertSlot(schedule.Id, firstStart.addMinutes(20), firstStart.addMinutes(40), 'Free');
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, oldSlot, TYPE_CHECKUP, 'Booked');

        Test.startTest();
        AppointmentCalendarController.ActionResult result = AppointmentCalendarController.rescheduleAppointment(
            appointment.Id,
            newSlot.Id
        );
        Test.stopTest();

        Appointment__c saved = [
            SELECT Slot__c, Start__c, End__c, Status__c, Practitioner__c, Location_Name__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        Slot__c oldAfter = [SELECT Status__c FROM Slot__c WHERE Id = :oldSlot.Id];
        Slot__c newAfter = [SELECT Status__c FROM Slot__c WHERE Id = :newSlot.Id];

        System.assertEquals(true, result.success, 'Successful reschedule should return success=true');
        System.assertEquals(null, result.reason, 'Successful reschedule should not set a failure reason');
        System.assertEquals(appointment.Id, result.appointmentId, 'Reschedule should return the same appointment');
        System.assertEquals(appointment.Id, result.appointment.Id, 'Result appointment should be the moved record');
        System.assertEquals(newSlot.Id, result.appointment.Slot__c, 'Result appointment should reference the new slot');
        System.assertEquals(oldSlot.Id, result.freedSlotId, 'Result should identify the freed slot');
        System.assertEquals(newSlot.Id, result.busiedSlotId, 'Result should identify the busied slot');
        System.assertEquals(newSlot.Id, result.slotId, 'Result should point at the new slot');
        System.assertEquals('Busy', result.slotStatus, 'New slot should be Busy in the result');
        System.assertEquals(oldSlot.Id, result.previousSlotId, 'Result should identify the freed slot');
        System.assertEquals('Free', result.previousSlotStatus, 'Old slot should be Free in the result');
        System.assertEquals(newSlot.Id, saved.Slot__c, 'Appointment should move to the new slot');
        System.assertEquals(newSlot.Start__c, saved.Start__c, 'Appointment start should copy from the new slot');
        System.assertEquals(newSlot.End__c, saved.End__c, 'Appointment end should copy from the new slot');
        System.assertEquals('Booked', saved.Status__c, 'Reschedule should leave status Booked');
        System.assertEquals(practitioner.Id, saved.Practitioner__c, 'Practitioner should come from the new slot schedule');
        System.assertEquals('Clinic A', saved.Location_Name__c, 'Location should come from the new slot schedule');
        System.assertEquals('Free', oldAfter.Status__c, 'Old slot must be freed');
        System.assertEquals('Busy', newAfter.Status__c, 'New slot must be busied');
    }

    @IsTest
    static void rescheduleBusyTargetReturnsFailureAndLeavesStateIntact() {
        Patient__c patient = insertPatient('MRN-CAL-SNAP');
        Practitioner__c practitioner = insertPractitioner('Hana', 'Cho');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic Snap');
        Datetime firstStart = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Slot__c oldSlot = insertSlot(schedule.Id, firstStart, firstStart.addMinutes(20), 'Busy');
        Slot__c busyTarget = insertSlot(schedule.Id, firstStart.addMinutes(20), firstStart.addMinutes(40), 'Busy');
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, oldSlot, TYPE_CHECKUP, 'Booked');
        Datetime originalStart = appointment.Start__c;
        Datetime originalEnd = appointment.End__c;

        Test.startTest();
        AppointmentCalendarController.ActionResult result = AppointmentCalendarController.rescheduleAppointment(
            appointment.Id,
            busyTarget.Id
        );
        Test.stopTest();

        Appointment__c saved = [
            SELECT Slot__c, Start__c, End__c, Status__c, Practitioner__c, Location_Name__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        Slot__c oldAfter = [SELECT Status__c FROM Slot__c WHERE Id = :oldSlot.Id];
        Slot__c targetAfter = [SELECT Status__c FROM Slot__c WHERE Id = :busyTarget.Id];

        System.assertEquals(false, result.success, 'Busy target is the snap-back path and must return success=false');
        System.assertEquals(true, String.isNotBlank(result.reason), 'Failure result must explain why the move was rejected');
        System.assertEquals(true, result.reason.contains('Busy'), 'Reason should say the target slot is Busy');
        System.assertEquals(appointment.Id, result.appointment.Id, 'Failure should still return the original appointment');
        System.assertEquals(oldSlot.Id, result.appointment.Slot__c, 'Failure appointment must still point at the original slot');
        System.assertEquals(null, result.freedSlotId, 'Failure must not report a freed slot');
        System.assertEquals(null, result.busiedSlotId, 'Failure must not report a busied slot');
        System.assertEquals(oldSlot.Id, saved.Slot__c, 'Appointment must stay on the original slot');
        System.assertEquals(originalStart, saved.Start__c, 'Appointment start must stay unchanged');
        System.assertEquals(originalEnd, saved.End__c, 'Appointment end must stay unchanged');
        System.assertEquals('Booked', saved.Status__c, 'Appointment status must stay Booked');
        System.assertEquals(practitioner.Id, saved.Practitioner__c, 'Practitioner must stay unchanged');
        System.assertEquals('Clinic Snap', saved.Location_Name__c, 'Location must stay unchanged');
        System.assertEquals('Busy', oldAfter.Status__c, 'Original slot must remain Busy');
        System.assertEquals('Busy', targetAfter.Status__c, 'Target slot must remain Busy');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :oldSlot.Id],
            'No extra appointment should be created on the original slot'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :busyTarget.Id],
            'No appointment should be moved onto the Busy target'
        );
    }

    @IsTest
    static void createAdHocSlotsInsertsAndSkipsOverlaps() {
        Practitioner__c practitioner = insertPractitioner('Jules', 'Kim');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic AdHoc');
        Datetime nine = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Slot__c existing = insertSlot(schedule.Id, nine, nine.addMinutes(20), 'Free');

        List<AppointmentCalendarController.SlotRange> ranges = new List<AppointmentCalendarController.SlotRange>{
            slotRange(nine, nine.addMinutes(20)),
            slotRange(nine.addMinutes(20), nine.addMinutes(40)),
            slotRange(nine.addMinutes(20), nine.addMinutes(40)),
            slotRange(nine.addMinutes(10), nine.addMinutes(30)),
            slotRange(nine.addMinutes(30), nine.addMinutes(50)),
            slotRange(nine.addHours(1), nine.addHours(1).addMinutes(20)),
            slotRange(nine.addHours(2), nine.addHours(2)),
            null
        };

        Test.startTest();
        AppointmentCalendarController.AdHocSlotResult result = AppointmentCalendarController.createAdHocSlots(
            schedule.Id,
            ranges,
            'Free'
        );
        AppointmentCalendarController.AdHocSlotResult empty = AppointmentCalendarController.createAdHocSlots(
            schedule.Id,
            new List<AppointmentCalendarController.SlotRange>(),
            null
        );
        AppointmentCalendarController.AdHocSlotResult none = AppointmentCalendarController.createAdHocSlots(
            schedule.Id,
            null,
            null
        );
        Schedule__c doomed = insertSchedule(practitioner.Id, 'Gone');
        Id missingScheduleId = doomed.Id;
        delete doomed;
        Boolean missingSchedule = false;
        Boolean deletedSchedule = false;
        Boolean badStatus = false;
        try {
            AppointmentCalendarController.createAdHocSlots(null, ranges, 'Free');
        } catch (AuraHandledException e) {
            missingSchedule = true;
        }
        try {
            AppointmentCalendarController.createAdHocSlots(missingScheduleId, ranges, 'Free');
        } catch (AuraHandledException e) {
            deletedSchedule = true;
        }
        try {
            AppointmentCalendarController.createAdHocSlots(schedule.Id, ranges, 'Busy');
        } catch (AuraHandledException e) {
            badStatus = true;
        }
        Test.stopTest();

        List<Slot__c> stored = [
            SELECT Id, Start__c, End__c, Status__c, Schedule__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c
        ];
        Set<Id> createdIds = new Set<Id>();
        for (Slot__c created : result.slots) {
            createdIds.add(created.Id);
        }

        System.assertEquals(true, result.success, 'Ad-hoc create should succeed even when some ranges are skipped');
        System.assertEquals(2, result.created, 'Only non-overlapping painted ranges should be inserted');
        System.assertEquals(5, result.skipped, 'Overlaps, duplicates, and invalid ranges should be skipped');
        System.assertEquals(2, result.slots.size(), 'Result should return the inserted slots');
        System.assertEquals(3, stored.size(), 'Schedule should keep the existing slot plus two new ones');
        System.assertEquals(existing.Id, stored[0].Id, 'Existing overlapping slot must be left in place');
        System.assertEquals(nine.addMinutes(20), stored[1].Start__c, 'First inserted slot should start when the existing slot ends');
        System.assertEquals(nine.addMinutes(40), stored[1].End__c, 'First inserted slot should use the painted end');
        System.assertEquals('Free', stored[1].Status__c, 'Ad-hoc slots must be Free');
        System.assertEquals(nine.addHours(1), stored[2].Start__c, 'Second inserted slot should be the non-overlapping 10:00 range');
        System.assertEquals(true, createdIds.contains(stored[1].Id), 'Result should include the 9:20 slot Id');
        System.assertEquals(true, createdIds.contains(stored[2].Id), 'Result should include the 10:00 slot Id');
        System.assertEquals(false, createdIds.contains(existing.Id), 'Existing slots must not be re-inserted');
        System.assertEquals(true, empty.success, 'Empty paint list should still succeed');
        System.assertEquals(0, empty.created, 'Empty paint list should insert nothing');
        System.assertEquals(0, empty.skipped, 'Empty paint list has nothing to skip');
        System.assertEquals(true, none.success, 'Null paint list should still succeed');
        System.assertEquals(0, none.created, 'Null paint list should insert nothing');
        System.assertEquals(true, missingSchedule, 'Ad-hoc create without a schedule should throw');
        System.assertEquals(true, deletedSchedule, 'Ad-hoc create against a deleted schedule should throw');
        System.assertEquals(true, badStatus, 'Busy is not a valid paint status');
    }

    @IsTest
    static void createAdHocSlotsCanPaintBlocked() {
        Practitioner__c practitioner = insertPractitioner('Nora', 'Voss');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic Block');
        Datetime nine = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        List<AppointmentCalendarController.SlotRange> ranges = new List<AppointmentCalendarController.SlotRange>{
            slotRange(nine, nine.addMinutes(40))
        };

        Test.startTest();
        AppointmentCalendarController.AdHocSlotResult result = AppointmentCalendarController.createAdHocSlots(
            schedule.Id,
            ranges,
            'Blocked'
        );
        Test.stopTest();

        System.assertEquals(1, result.created, 'Blocked paint should insert one slot');
        System.assertEquals('Blocked', result.slots[0].Status__c, 'Painted slot status should be Blocked');
        System.assertEquals(
            'Blocked',
            [SELECT Block_Reason__c FROM Slot__c WHERE Id = :result.slots[0].Id].Block_Reason__c,
            'Blocked paint should stamp a block reason'
        );
    }

    @IsTest
    static void bookAppointmentLocksSlotAndRejectsBusyWithoutChanges() {
        Patient__c patient = insertPatient('MRN-CAL-BK');
        Practitioner__c practitioner = insertPractitioner('Liam', 'Ortiz');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic Book');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(11, 0, 0, 0));
        Slot__c freeSlot = insertSlot(schedule.Id, startTime, startTime.addMinutes(20), 'Free');
        Slot__c busySlot = insertSlot(schedule.Id, startTime.addMinutes(20), startTime.addMinutes(40), 'Busy');

        Test.startTest();
        AppointmentCalendarController.ActionResult booked = AppointmentCalendarController.bookAppointment(
            patient.Id,
            freeSlot.Id,
            TYPE_CHECKUP,
            'Walk-in paint'
        );
        AppointmentCalendarController.ActionResult rejected = AppointmentCalendarController.bookAppointment(
            insertPatient('MRN-CAL-BK2').Id,
            busySlot.Id,
            TYPE_CHECKUP,
            'Too late'
        );
        Boolean secondBookRejected = false;
        AppointmentCalendarController.ActionResult second = AppointmentCalendarController.bookAppointment(
            insertPatient('MRN-CAL-BK3').Id,
            freeSlot.Id,
            'Follow-up',
            null
        );
        if (second.success == false) {
            secondBookRejected = true;
        }
        Boolean missingPatient = false;
        try {
            AppointmentCalendarController.bookAppointment(null, freeSlot.Id, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        Boolean unknownPatient = false;
        try {
            AppointmentCalendarController.bookAppointment(UserInfo.getUserId(), freeSlot.Id, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            unknownPatient = true;
        }
        Boolean missingSlot = false;
        try {
            AppointmentCalendarController.bookAppointment(patient.Id, null, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            missingSlot = true;
        }
        Boolean badType = false;
        try {
            AppointmentCalendarController.bookAppointment(patient.Id, freeSlot.Id, 'Not-a-type', null);
        } catch (AuraHandledException e) {
            badType = true;
        }
        Boolean orphanSlot = false;
        Slot__c orphan = insertSlot(
            insertSchedule(null, null).Id,
            startTime.addHours(2),
            startTime.addHours(2).addMinutes(20),
            'Free'
        );
        try {
            AppointmentCalendarController.bookAppointment(patient.Id, orphan.Id, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            orphanSlot = true;
        }
        Boolean missingSlotRecord = false;
        Slot__c ghost = insertSlot(schedule.Id, startTime.addHours(3), startTime.addHours(3).addMinutes(20), 'Free');
        Id ghostId = ghost.Id;
        delete ghost;
        try {
            AppointmentCalendarController.bookAppointment(patient.Id, ghostId, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            missingSlotRecord = true;
        }
        Boolean blankType = false;
        try {
            AppointmentCalendarController.bookAppointment(patient.Id, freeSlot.Id, '  ', null);
        } catch (AuraHandledException e) {
            blankType = true;
        }
        Test.stopTest();

        Appointment__c saved = [
            SELECT Patient__c, Practitioner__c, Slot__c, Start__c, End__c, Status__c, Appointment_Type__c, Reason__c
            FROM Appointment__c
            WHERE Id = :booked.appointmentId
        ];
        System.assertEquals(true, booked.success, 'Book of a Free slot should succeed');
        System.assertEquals(saved.Id, booked.appointment.Id, 'Book result should include the created appointment');
        System.assertEquals(freeSlot.Id, booked.busiedSlotId, 'Book should report the busied slot');
        System.assertEquals('Busy', booked.slotStatus, 'Booked slot status in the result should be Busy');
        System.assertEquals(patient.Id, saved.Patient__c, 'Book should stamp the patient');
        System.assertEquals(practitioner.Id, saved.Practitioner__c, 'Book should stamp the schedule practitioner');
        System.assertEquals(freeSlot.Id, saved.Slot__c, 'Book should attach the locked slot');
        System.assertEquals('Booked', saved.Status__c, 'New appointment status should be Booked');
        System.assertEquals('Walk-in paint', saved.Reason__c, 'Reason should be stored');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :freeSlot.Id].Status__c, 'Booked slot must be Busy');
        System.assertEquals(false, rejected.success, 'Book against a Busy slot should return success=false');
        System.assertEquals(true, String.isNotBlank(rejected.reason), 'Busy book should return a reason');
        System.assertEquals(0, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :busySlot.Id], 'Busy book must not insert an appointment');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :busySlot.Id].Status__c, 'Already-Busy slot must stay Busy');
        System.assertEquals(true, secondBookRejected, 'A second book against the now-Busy slot must fail');
        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :freeSlot.Id], 'Only the first book should persist');
        System.assertEquals(true, missingPatient, 'Book without a patient should throw');
        System.assertEquals(true, unknownPatient, 'Book with a non-patient Id should throw');
        System.assertEquals(true, missingSlot, 'Book without a slot should throw');
        System.assertEquals(true, badType, 'Book with an invalid type should throw');
        System.assertEquals(true, orphanSlot, 'Book onto a slot without a provider should throw');
        System.assertEquals(true, missingSlotRecord, 'Book against a deleted slot should throw');
        System.assertEquals(true, blankType, 'Book with a blank type should throw');
    }

    @IsTest
    static void arriveCreatesEncounterLinkedToAppointment() {
        Patient__c patient = insertPatient('MRN-CAL-AR');
        Practitioner__c practitioner = insertPractitioner('Ben', 'Ng');
        Slot__c slot = insertSlot(
            insertSchedule(practitioner.Id, 'Clinic B').Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(10, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(10, 20, 0, 0)),
            'Busy'
        );
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, slot, TYPE_CHECKUP, 'Booked');
        appointment.Reason__c = 'Sore throat';
        appointment.Location_Name__c = 'Clinic B';
        update appointment;
        Datetime beforeArrive = Datetime.now().addMinutes(-1);

        Test.startTest();
        AppointmentCalendarController.ActionResult result = AppointmentCalendarController.arriveAppointment(
            appointment.Id
        );
        Test.stopTest();

        Appointment__c saved = [
            SELECT Status__c, Encounter__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        Encounter__c encounter = [
            SELECT
                Patient__c,
                Practitioner__c,
                Start__c,
                Status__c,
                Class__c,
                Location_Name__c,
                Reason__c,
                Name
            FROM Encounter__c
            WHERE Id = :saved.Encounter__c
        ];

        System.assertEquals(true, result.success, 'Arrive should return success=true');
        System.assertEquals(appointment.Id, result.appointment.Id, 'Arrive result should include the appointment');
        System.assertEquals(encounter.Id, result.appointment.Encounter__c, 'Arrive result appointment should reference the encounter');
        System.assertEquals('Arrived', result.appointmentStatus, 'Appointment status in the result should be Arrived');
        System.assertEquals(encounter.Id, result.encounterId, 'Result should return the new encounter Id');
        System.assertEquals(true, String.isNotBlank(result.encounterName), 'Result should include the encounter name');
        System.assertEquals('Arrived', saved.Status__c, 'Appointment status should be Arrived');
        System.assertEquals(encounter.Id, saved.Encounter__c, 'Appointment.Encounter__c should point at the created encounter');
        System.assertEquals(patient.Id, encounter.Patient__c, 'Encounter patient should match the appointment');
        System.assertEquals(practitioner.Id, encounter.Practitioner__c, 'Encounter practitioner should match the appointment');
        System.assertEquals('Arrived', encounter.Status__c, 'Encounter status should be Arrived');
        System.assertEquals('Outpatient', encounter.Class__c, 'Checkup should default encounter class to Outpatient');
        System.assertEquals('Clinic B', encounter.Location_Name__c, 'Encounter location should copy from the appointment');
        System.assertEquals('Sore throat', encounter.Reason__c, 'Encounter reason should copy from the appointment');
        System.assertEquals(true, encounter.Start__c >= beforeArrive, 'Encounter start should be now, not the slot start');
        System.assertEquals(1, [SELECT COUNT() FROM Encounter__c WHERE Patient__c = :patient.Id], 'Arrive should insert exactly one encounter');
    }

    @IsTest
    static void arriveEmergencyMapsClassAndRejectsSecondArrive() {
        Patient__c patient = insertPatient('MRN-CAL-EM');
        Practitioner__c practitioner = insertPractitioner('Cara', 'Singh');
        Slot__c slot = insertSlot(
            insertSchedule(practitioner.Id, 'ER').Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(11, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(11, 20, 0, 0)),
            'Busy'
        );
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, slot, TYPE_EMERGENCY, 'Booked');

        Test.startTest();
        AppointmentCalendarController.ActionResult first = AppointmentCalendarController.arriveAppointment(
            appointment.Id
        );
        Boolean secondRejected = false;
        try {
            AppointmentCalendarController.arriveAppointment(appointment.Id);
        } catch (AuraHandledException e) {
            secondRejected = true;
        }
        Test.stopTest();

        Encounter__c encounter = [SELECT Class__c, Status__c FROM Encounter__c WHERE Id = :first.encounterId];
        System.assertEquals('Emergency', encounter.Class__c, 'Emergency appointment type should map to Emergency class');
        System.assertEquals('Arrived', encounter.Status__c, 'Created encounter should be Arrived');
        System.assertEquals(true, secondRejected, 'A second arrive should be rejected');
        System.assertEquals(1, [SELECT COUNT() FROM Encounter__c], 'Second arrive must not insert another encounter');
    }

    @IsTest
    static void getGridReturnsSlotsAppointmentsAndFilters() {
        Practitioner__c practitioner = insertPractitioner('Drew', 'Patel');
        Practitioner__c other = insertPractitioner('Eli', 'Park');
        Schedule__c clinicA = insertSchedule(practitioner.Id, 'Clinic A');
        Schedule__c clinicB = insertSchedule(practitioner.Id, 'Clinic B');
        Schedule__c otherSchedule = insertSchedule(other.Id, 'Clinic A');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Slot__c bookedSlot = insertSlot(clinicA.Id, startTime, startTime.addMinutes(20), 'Busy');
        Slot__c freeSlot = insertSlot(clinicA.Id, startTime.addMinutes(20), startTime.addMinutes(40), 'Free');
        insertSlot(clinicA.Id, startTime.addMinutes(40), startTime.addMinutes(60), 'Blocked');
        insertSlot(clinicB.Id, startTime.addHours(1), startTime.addHours(1).addMinutes(20), 'Free');
        insertSlot(otherSchedule.Id, startTime, startTime.addMinutes(20), 'Free');
        Patient__c patient = insertPatient('MRN-CAL-GR');
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, bookedSlot, TYPE_CHECKUP, 'Booked');

        Test.startTest();
        List<String> allLocations = AppointmentCalendarController.getLocations(null);
        List<String> providerLocations = AppointmentCalendarController.getLocations(practitioner.Id);
        AppointmentCalendarController.GridView providerGrid = AppointmentCalendarController.getGrid(
            practitioner.Id,
            null,
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.GridView clinicAGrid = AppointmentCalendarController.getGrid(
            practitioner.Id,
            'Clinic A',
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.GridView locationOnly = AppointmentCalendarController.getGrid(
            null,
            'Clinic A',
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.GridView allGrid = AppointmentCalendarController.getGrid(
            null,
            null,
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.GridView bothProviders = AppointmentCalendarController.getGridForProviders(
            new List<Id>{ practitioner.Id, other.Id },
            null,
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.GridView otherOnly = AppointmentCalendarController.getGridForProviders(
            new List<Id>{ other.Id },
            null,
            SLOT_DAY,
            SLOT_DAY
        );
        Test.stopTest();

        System.assertEquals(true, allLocations.contains('Clinic A'), 'Unfiltered locations should include Clinic A');
        System.assertEquals(true, allLocations.contains('Clinic B'), 'Unfiltered locations should include Clinic B');
        System.assertEquals(new List<String>{ 'Clinic A', 'Clinic B' }, providerLocations, 'Provider locations should be distinct and sorted');
        System.assertEquals(4, providerGrid.slots.size(), 'Provider grid should include Free, Busy, and Blocked slots');
        System.assertEquals(false, providerGrid.hasMore, 'Four slots should not exceed the grid limit');
        System.assertEquals(20, providerGrid.slotDurationMinutes, 'Grid should surface the schedule slot duration');
        System.assertEquals(3, clinicAGrid.slots.size(), 'Location + provider should return only Clinic A slots');
        System.assertEquals(4, locationOnly.slots.size(), 'Location-only should include both providers at Clinic A');
        System.assertEquals(5, allGrid.slots.size(), 'Unfiltered grid should include every active-schedule slot');
        System.assertEquals(5, bothProviders.slots.size(), 'Selecting both providers should return every slot');
        System.assertEquals(1, otherOnly.slots.size(), 'Selecting one provider should hide the other provider slots');
        System.assertEquals(other.Id, otherOnly.slots[0].practitionerId, 'Filtered grid should belong to the selected provider');

        AppointmentCalendarController.SlotView bookedView;
        AppointmentCalendarController.SlotView freeView;
        AppointmentCalendarController.SlotView blockedView;
        for (AppointmentCalendarController.SlotView row : clinicAGrid.slots) {
            if (row.id == bookedSlot.Id) {
                bookedView = row;
            } else if (row.id == freeSlot.Id) {
                freeView = row;
            } else if (row.status == 'Blocked') {
                blockedView = row;
            }
        }
        System.assertNotEquals(null, bookedView, 'Busy booked slot should appear on the grid');
        System.assertEquals('Busy', bookedView.status, 'Booked slot status should be Busy');
        System.assertNotEquals(null, bookedView.appointment, 'Busy slot should include its appointment');
        System.assertEquals(appointment.Id, bookedView.appointment.id, 'Grid appointment should match the booked record');
        System.assertEquals(patient.Id, bookedView.appointment.patientId, 'Grid appointment should include the patient');
        System.assertEquals('Booked', bookedView.appointment.status, 'Grid appointment status should be Booked');
        System.assertEquals(practitioner.Id, bookedView.practitionerId, 'Slot view should include the provider');
        System.assertEquals(clinicA.Id, bookedView.scheduleId, 'Slot view should include the schedule Id');
        System.assertEquals(clinicA.Id, clinicAGrid.defaultScheduleId, 'Grid should surface a default schedule for ad-hoc painting');
        System.assertEquals('Clinic A', bookedView.locationName, 'Slot view should include the schedule location');
        List<AppointmentCalendarController.ScheduleOption> schedules = AppointmentCalendarController.getActiveSchedules(
            practitioner.Id,
            'Clinic A'
        );
        System.assertEquals(1, schedules.size(), 'Active schedules should honor the location filter');
        System.assertEquals(clinicA.Id, schedules[0].id, 'Filtered schedule should be Clinic A');
        System.assertEquals(
            2,
            AppointmentCalendarController.getActiveSchedules(practitioner.Id, null).size(),
            'Provider schedules should include both Clinic A and Clinic B'
        );
        System.assertEquals(
            3,
            AppointmentCalendarController.getActiveSchedulesForProviders(
                new List<Id>{ practitioner.Id, other.Id },
                null
            ).size(),
            'Schedules for both providers should include Clinic A, Clinic B, and the other Clinic A'
        );
        System.assertEquals(
            3,
            AppointmentCalendarController.getActiveSchedules(null, null).size(),
            'Unfiltered schedules should include every active schedule'
        );
        System.assertEquals(
            true,
            AppointmentCalendarController.getActiveSchedules(null, 'Clinic A').size() >= 2,
            'Location-only schedules should include every active Clinic A schedule'
        );
        System.assertEquals('Free', freeView.status, 'Free slot should remain Free on the grid');
        System.assertEquals(null, freeView.appointment, 'Free slot should not show an appointment');
        System.assertEquals('Blocked', blockedView.status, 'Blocked slot should appear on the grid');
    }

    @IsTest
    static void cancelFreesSlotAndNoShowLeavesSlotBusy() {
        Patient__c patient = insertPatient('MRN-CAL-CN');
        Practitioner__c practitioner = insertPractitioner('Fay', 'Ortiz');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic C');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(13, 0, 0, 0));
        Slot__c cancelSlot = insertSlot(schedule.Id, startTime, startTime.addMinutes(20), 'Busy');
        Slot__c noShowSlot = insertSlot(schedule.Id, startTime.addMinutes(20), startTime.addMinutes(40), 'Busy');
        Appointment__c toCancel = insertAppointment(patient.Id, practitioner.Id, cancelSlot, TYPE_CHECKUP, 'Booked');
        Appointment__c toNoShow = insertAppointment(
            insertPatient('MRN-CAL-NS').Id,
            practitioner.Id,
            noShowSlot,
            TYPE_CHECKUP,
            'Booked'
        );

        Test.startTest();
        AppointmentCalendarController.ActionResult cancelled = AppointmentCalendarController.cancelAppointment(
            toCancel.Id
        );
        AppointmentCalendarController.ActionResult noShow = AppointmentCalendarController.markNoShow(toNoShow.Id);
        Test.stopTest();

        System.assertEquals(true, cancelled.success, 'Cancel should return success=true');
        System.assertEquals(toCancel.Id, cancelled.appointment.Id, 'Cancel result should include the appointment');
        System.assertEquals(cancelSlot.Id, cancelled.freedSlotId, 'Cancel should report the freed slot');
        System.assertEquals('Cancelled', cancelled.appointmentStatus, 'Cancel should set appointment status to Cancelled');
        System.assertEquals('Free', cancelled.slotStatus, 'Cancel should free the slot');
        System.assertEquals('Free', [SELECT Status__c FROM Slot__c WHERE Id = :cancelSlot.Id].Status__c, 'Cancelled appointment slot must be Free');
        System.assertEquals(true, noShow.success, 'No Show should return success=true');
        System.assertEquals(toNoShow.Id, noShow.appointment.Id, 'No Show result should include the appointment');
        System.assertEquals(noShowSlot.Id, noShow.busiedSlotId, 'No Show should leave its slot identified as still Busy');
        System.assertEquals('No Show', noShow.appointmentStatus, 'No Show should set appointment status');
        System.assertEquals('Busy', noShow.slotStatus, 'No Show should leave the slot Busy');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :noShowSlot.Id].Status__c, 'No-show slot must stay Busy');

        AppointmentCalendarController.GridView grid = AppointmentCalendarController.getGrid(
            practitioner.Id,
            'Clinic C',
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentCalendarController.SlotView cancelView;
        AppointmentCalendarController.SlotView noShowView;
        for (AppointmentCalendarController.SlotView row : grid.slots) {
            if (row.id == cancelSlot.Id) {
                cancelView = row;
            } else if (row.id == noShowSlot.Id) {
                noShowView = row;
            }
        }
        System.assertEquals(null, cancelView.appointment, 'Cancelled appointment should not overlay a freed slot');
        System.assertNotEquals(null, noShowView.appointment, 'No-show appointment should still overlay its Busy slot');
        System.assertEquals('No Show', noShowView.appointment.status, 'Grid should show No Show status');
    }

    @IsTest
    static void cancelAndRescheduleWorkWithoutCurrentSlot() {
        Patient__c patient = insertPatient('MRN-CAL-NOSLOT');
        Practitioner__c practitioner = insertPractitioner('Ivy', 'Shaw');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic E');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(15, 0, 0, 0));
        Slot__c newSlot = insertSlot(schedule.Id, startTime, startTime.addMinutes(20), 'Free');
        Appointment__c toMove = insertAppointment(patient.Id, practitioner.Id, null, TYPE_CHECKUP, 'Booked');
        Appointment__c toCancel = insertAppointment(
            insertPatient('MRN-CAL-NOSLOT2').Id,
            practitioner.Id,
            null,
            TYPE_CHECKUP,
            'Booked'
        );

        Test.startTest();
        AppointmentCalendarController.ActionResult moved = AppointmentCalendarController.rescheduleAppointment(
            toMove.Id,
            newSlot.Id
        );
        AppointmentCalendarController.ActionResult cancelled = AppointmentCalendarController.cancelAppointment(
            toCancel.Id
        );
        Test.stopTest();

        System.assertEquals(newSlot.Id, moved.slotId, 'Reschedule without a current slot should assign the new slot');
        System.assertEquals('Busy', moved.slotStatus, 'New slot should be Busy');
        System.assertEquals(null, moved.previousSlotId, 'There should be no previous slot to free');
        System.assertEquals(newSlot.Id, [SELECT Slot__c FROM Appointment__c WHERE Id = :toMove.Id].Slot__c, 'Moved appointment should reference the new slot');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :newSlot.Id].Status__c, 'Target slot should be Busy');
        System.assertEquals('Cancelled', cancelled.appointmentStatus, 'Slotless cancel should still cancel the appointment');
        System.assertEquals(null, cancelled.slotId, 'Slotless cancel should not report a slot');
        System.assertEquals('Cancelled', [SELECT Status__c FROM Appointment__c WHERE Id = :toCancel.Id].Status__c, 'Cancelled appointment status should persist');
    }

    @IsTest
    static void actionAndGridValidationErrors() {
        Patient__c patient = insertPatient('MRN-CAL-VAL');
        Practitioner__c practitioner = insertPractitioner('Gus', 'Reed');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic D');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(14, 0, 0, 0));
        Slot__c bookedSlot = insertSlot(schedule.Id, startTime, startTime.addMinutes(20), 'Busy');
        Slot__c busySlot = insertSlot(schedule.Id, startTime.addMinutes(20), startTime.addMinutes(40), 'Busy');
        Slot__c orphanSlot = insertSlot(
            insertSchedule(null, null).Id,
            startTime.addMinutes(40),
            startTime.addMinutes(60),
            'Free'
        );
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id, bookedSlot, TYPE_CHECKUP, 'Booked');
        Appointment__c cancelled = insertAppointment(
            insertPatient('MRN-CAL-VAL2').Id,
            practitioner.Id,
            insertSlot(schedule.Id, startTime.addHours(1), startTime.addHours(1).addMinutes(20), 'Free'),
            TYPE_CHECKUP,
            'Cancelled'
        );
        Id missingAppointmentId = cancelled.Id;
        delete cancelled;

        Test.startTest();
        Boolean gridNoFilter = threwOnGrid(null, null, SLOT_DAY, SLOT_DAY);
        Boolean gridNoDates = threwOnGrid(practitioner.Id, null, null, SLOT_DAY);
        Boolean gridRange = threwOnGrid(practitioner.Id, null, SLOT_DAY, SLOT_DAY.addDays(-1));
        Boolean rescheduleNoAppt = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(null, busySlot.Id);
        } catch (AuraHandledException e) {
            rescheduleNoAppt = true;
        }
        Boolean rescheduleNoSlot = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(appointment.Id, null);
        } catch (AuraHandledException e) {
            rescheduleNoSlot = true;
        }
        Boolean rescheduleSame = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(appointment.Id, bookedSlot.Id);
        } catch (AuraHandledException e) {
            rescheduleSame = true;
        }
        AppointmentCalendarController.ActionResult rescheduleBusyResult = AppointmentCalendarController.rescheduleAppointment(
            appointment.Id,
            busySlot.Id
        );
        Boolean rescheduleOrphan = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(appointment.Id, orphanSlot.Id);
        } catch (AuraHandledException e) {
            rescheduleOrphan = true;
        }
        Boolean rescheduleMissing = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(missingAppointmentId, orphanSlot.Id);
        } catch (AuraHandledException e) {
            rescheduleMissing = true;
        }
        Boolean cancelMissing = false;
        try {
            AppointmentCalendarController.cancelAppointment(null);
        } catch (AuraHandledException e) {
            cancelMissing = true;
        }
        Boolean noShowCancelled = false;
        Appointment__c alreadyCancelled = insertAppointment(
            insertPatient('MRN-CAL-VAL3').Id,
            practitioner.Id,
            insertSlot(schedule.Id, startTime.addHours(2), startTime.addHours(2).addMinutes(20), 'Free'),
            TYPE_CHECKUP,
            'Cancelled'
        );
        try {
            AppointmentCalendarController.markNoShow(alreadyCancelled.Id);
        } catch (AuraHandledException e) {
            noShowCancelled = true;
        }
        Boolean rescheduleCancelled = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(alreadyCancelled.Id, orphanSlot.Id);
        } catch (AuraHandledException e) {
            rescheduleCancelled = true;
        }
        Boolean cancelTwice = false;
        Appointment__c bookedThenCancel = insertAppointment(
            insertPatient('MRN-CAL-VAL4').Id,
            practitioner.Id,
            insertSlot(schedule.Id, startTime.addHours(3), startTime.addHours(3).addMinutes(20), 'Busy'),
            TYPE_CHECKUP,
            'Booked'
        );
        AppointmentCalendarController.cancelAppointment(bookedThenCancel.Id);
        try {
            AppointmentCalendarController.cancelAppointment(bookedThenCancel.Id);
        } catch (AuraHandledException e) {
            cancelTwice = true;
        }
        Boolean missingNewSlot = false;
        try {
            AppointmentCalendarController.rescheduleAppointment(appointment.Id, missingAppointmentId);
        } catch (AuraHandledException e) {
            missingNewSlot = true;
        }
        Boolean arriveMissing = false;
        try {
            AppointmentCalendarController.arriveAppointment(null);
        } catch (AuraHandledException e) {
            arriveMissing = true;
        }
        Test.stopTest();

        System.assertEquals(false, gridNoFilter, 'Grid without provider or location should load all active slots');
        System.assertEquals(true, gridNoDates, 'Grid without dates should throw');
        System.assertEquals(true, gridRange, 'Inverted grid range should throw');
        System.assertEquals(true, rescheduleNoAppt, 'Reschedule without an appointment should throw');
        System.assertEquals(true, rescheduleNoSlot, 'Reschedule without a new slot should throw');
        System.assertEquals(true, rescheduleSame, 'Reschedule onto the same slot should throw');
        System.assertEquals(false, rescheduleBusyResult.success, 'Reschedule onto a Busy slot should return success=false');
        System.assertEquals(true, rescheduleOrphan, 'Reschedule onto a slot without a provider should throw');
        System.assertEquals(true, rescheduleMissing, 'Reschedule of a deleted appointment should throw');
        System.assertEquals(true, cancelMissing, 'Cancel without an appointment should throw');
        System.assertEquals(true, noShowCancelled, 'No Show on a cancelled appointment should throw');
        System.assertEquals(true, rescheduleCancelled, 'Reschedule of a cancelled appointment should throw');
        System.assertEquals(true, cancelTwice, 'Cancelling an already cancelled appointment should throw');
        System.assertEquals(true, missingNewSlot, 'Reschedule onto a missing slot should throw');
        System.assertEquals(true, arriveMissing, 'Arrive without an appointment should throw');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :bookedSlot.Id].Status__c, 'Failed reschedules must leave the original slot Busy');
        System.assertEquals(bookedSlot.Id, [SELECT Slot__c FROM Appointment__c WHERE Id = :appointment.Id].Slot__c, 'Failed reschedules must not move the appointment');
    }

    @IsTest
    static void getNextAvailabilityListsSoonestFreeSlotPerProvider() {
        Practitioner__c lee = insertPractitioner('Mina', 'Lee');
        lee.Specialty__c = 'Primary Care';
        update lee;
        Practitioner__c patel = insertPractitioner('Ravi', 'Patel');
        Practitioner__c empty = insertPractitioner('Sofia', 'Vasquez');
        Practitioner__c inactive = insertPractitioner('Cara', 'Singh');
        inactive.Active__c = false;
        update inactive;
        Schedule__c leeClinicA = insertSchedule(lee.Id, 'Clinic A');
        Schedule__c leeClinicB = insertSchedule(lee.Id, 'Clinic B');
        Schedule__c patelClinicA = insertSchedule(patel.Id, 'Clinic A');
        insertSchedule(empty.Id, 'Clinic A');
        insertSchedule(inactive.Id, 'Clinic A');
        Datetime past = Datetime.now().addDays(-1);
        Datetime leeSoon = Datetime.now().addDays(2);
        Datetime leeLater = Datetime.now().addDays(5);
        Datetime patelSoon = Datetime.now().addDays(3);
        insert new List<Slot__c>{
            new Slot__c(Schedule__c = leeClinicA.Id, Start__c = past, End__c = past.addMinutes(20), Status__c = 'Free'),
            new Slot__c(
                Schedule__c = leeClinicA.Id,
                Start__c = leeSoon,
                End__c = leeSoon.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = leeClinicB.Id,
                Start__c = leeLater,
                End__c = leeLater.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = patelClinicA.Id,
                Start__c = patelSoon,
                End__c = patelSoon.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = leeClinicA.Id,
                Start__c = leeSoon.addHours(1),
                End__c = leeSoon.addHours(1).addMinutes(20),
                Status__c = 'Busy'
            )
        };

        Test.startTest();
        List<AppointmentCalendarController.NextAvailabilityView> allRows = AppointmentCalendarController.getNextAvailability(
            null
        );
        List<AppointmentCalendarController.NextAvailabilityView> clinicB = AppointmentCalendarController.getNextAvailability(
            'Clinic B'
        );
        Test.stopTest();

        System.assertEquals(3, allRows.size(), 'Active providers with a schedule should appear');
        AppointmentCalendarController.NextAvailabilityView leeView = findNextAvailability(allRows, lee.Id);
        AppointmentCalendarController.NextAvailabilityView patelView = findNextAvailability(allRows, patel.Id);
        AppointmentCalendarController.NextAvailabilityView emptyView = findNextAvailability(allRows, empty.Id);
        System.assertNotEquals(null, leeView, 'Lee should appear');
        System.assertEquals(leeSoon, leeView.nextStart, 'Lee should show the soonest future Free slot');
        System.assertEquals('Clinic A', leeView.locationName, 'Next opening should use that slot location');
        System.assertEquals('Primary Care', leeView.specialty, 'Specialty should come from the practitioner');
        System.assertEquals(patelSoon, patelView.nextStart, 'Patel should show their next Free slot');
        System.assertEquals(null, emptyView.nextStart, 'A provider with no upcoming Free slot should still be listed');
        System.assertEquals(null, findNextAvailability(allRows, inactive.Id), 'Inactive providers must be omitted');
        System.assertEquals(lee.Id, allRows[0].practitionerId, 'Soonest opening should sort first');
        System.assertEquals(1, clinicB.size(), 'Location filter should keep providers who have a schedule there');
        System.assertEquals(lee.Id, clinicB[0].practitionerId, 'Clinic B should return Lee');
        System.assertEquals(leeLater, clinicB[0].nextStart, 'Clinic B should use the Free slot at that location');
    }

    private static AppointmentCalendarController.NextAvailabilityView findNextAvailability(
        List<AppointmentCalendarController.NextAvailabilityView> rows,
        Id practitionerId
    ) {
        for (AppointmentCalendarController.NextAvailabilityView row : rows) {
            if (row.practitionerId == practitionerId) {
                return row;
            }
        }
        return null;
    }

    private static Boolean threwOnGrid(Id practitionerId, String locationName, Date rangeStart, Date rangeEnd) {
        try {
            AppointmentCalendarController.getGrid(practitionerId, locationName, rangeStart, rangeEnd);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Calendar');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(String firstName, String lastName) {
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = firstName, Last_Name__c = lastName);
        insert practitioner;
        return practitioner;
    }

    private static Schedule__c insertSchedule(Id practitionerId, String locationName) {
        Schedule__c schedule = new Schedule__c(
            Practitioner__c = practitionerId,
            Location_Name__c = locationName,
            Slot_Duration_Minutes__c = 20,
            Active__c = true
        );
        insert schedule;
        return schedule;
    }

    private static AppointmentCalendarController.SlotRange slotRange(Datetime startTime, Datetime endTime) {
        AppointmentCalendarController.SlotRange range = new AppointmentCalendarController.SlotRange();
        range.startTime = startTime;
        range.endTime = endTime;
        return range;
    }

    private static Slot__c insertSlot(Id scheduleId, Datetime startTime, Datetime endTime, String status) {
        Slot__c slot = new Slot__c(
            Schedule__c = scheduleId,
            Start__c = startTime,
            End__c = endTime,
            Status__c = status
        );
        insert slot;
        return slot;
    }

    private static Appointment__c insertAppointment(
        Id patientId,
        Id practitionerId,
        Slot__c slot,
        String appointmentType,
        String status
    ) {
        Datetime startTime = slot == null
            ? DateTime.newInstance(SLOT_DAY, Time.newInstance(8, 0, 0, 0))
            : slot.Start__c;
        Datetime endTime = slot == null ? startTime.addMinutes(20) : slot.End__c;
        String locationName;
        if (slot != null && slot.Schedule__c != null) {
            locationName = [SELECT Location_Name__c FROM Schedule__c WHERE Id = :slot.Schedule__c].Location_Name__c;
        }
        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Practitioner__c = practitionerId,
            Slot__c = slot == null ? null : slot.Id,
            Start__c = startTime,
            End__c = endTime,
            Location_Name__c = locationName,
            Appointment_Type__c = appointmentType,
            Status__c = status
        );
        insert appointment;
        return appointment;
    }
}
