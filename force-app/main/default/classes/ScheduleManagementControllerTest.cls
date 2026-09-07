@IsTest
private class ScheduleManagementControllerTest {
    private static final Date WEEK_START = Date.newInstance(2026, 9, 7);
    private static final Date WEEK_END = Date.newInstance(2026, 9, 13);

    @IsTest
    static void generateSlotsCreatesExpectedCountAndTimes() {
        Schedule__c schedule = insertScheduleWithHours(
            insertPractitioner('Ada', 'Lopez'),
            'Clinic A',
            20,
            weekdayHours('09:00', '17:00')
        );

        Test.startTest();
        ScheduleManagementController.GenerationPreview preview = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_END,
            null
        );
        ScheduleManagementController.GenerationResult result = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_END
        );
        Test.stopTest();

        // Mon–Fri, 09:00–17:00, 20-minute interval = 5 days × 24 slots.
        System.assertEquals(120, preview.slotCount, 'Preview should report 120 weekday slots');
        System.assertEquals(120, preview.freeCount, 'All generated slots should be Free without time off');
        System.assertEquals(false, preview.overLimit, '120 slots should be under the generation cap');
        System.assertEquals(0, preview.skippedExisting, 'No existing slots should be skipped on first preview');
        System.assertEquals(120, result.created, 'Generate should insert the previewed slot count');
        System.assertEquals(120, result.createdFree, 'Generated Free count should match');
        System.assertEquals(0, result.skippedExisting, 'No existing slots should be skipped on first generate');

        List<Slot__c> slots = [
            SELECT Start__c, End__c, Status__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c ASC
        ];
        System.assertEquals(120, slots.size(), 'Exactly 120 Slot__c rows should exist');
        System.assertEquals(
            DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0)),
            slots[0].Start__c,
            'First slot should start Monday 09:00'
        );
        System.assertEquals('Free', slots[0].Status__c, 'Generated slots should be Free');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Slot__c
                WHERE Schedule__c = :schedule.Id AND (Start__c = :weekendSaturday() OR Start__c = :weekendSunday())
            ],
            'Weekend days should be skipped when only weekdays have hours'
        );
    }

    @IsTest
    static void generateSlotsRespectsLunchGap() {
        List<ScheduleManagementController.HoursView> hours = new List<ScheduleManagementController.HoursView>();
        for (Integer day = 1; day <= 5; day++) {
            hours.add(hour(String.valueOf(day), '09:00', '12:00'));
            hours.add(hour(String.valueOf(day), '13:00', '17:00'));
        }
        Schedule__c schedule = insertScheduleWithHours(insertPractitioner('Ben', 'Ng'), null, 30, hours);

        Test.startTest();
        ScheduleManagementController.GenerationResult result = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        Test.stopTest();

        // Monday: 09–12 = 6 slots, 13–17 = 8 slots => 14.
        System.assertEquals(14, result.created, 'Lunch gap should split the day into two windows');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Slot__c
                WHERE
                    Schedule__c = :schedule.Id
                    AND Start__c >= :DateTime.newInstance(WEEK_START, Time.newInstance(12, 0, 0, 0))
                    AND Start__c < :DateTime.newInstance(WEEK_START, Time.newInstance(13, 0, 0, 0))
            ],
            'No slots should be created during the lunch gap'
        );
    }

    @IsTest
    static void generateSlotsIsBulkAndSkipsExisting() {
        Schedule__c schedule = insertScheduleWithHours(
            insertPractitioner('Cara', 'Singh'),
            null,
            30,
            weekdayHours('09:00', '17:00')
        );

        Test.startTest();
        ScheduleManagementController.GenerationResult first = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        Integer dmlAfterInsert = Limits.getDmlStatements();
        ScheduleManagementController.GenerationPreview preview = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            null
        );
        ScheduleManagementController.GenerationResult second = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        Test.stopTest();

        System.assertEquals(16, first.created, 'First generate inserts 16 slots');
        System.assertEquals(1, dmlAfterInsert, 'Slot generation must use one bulk insert, not insert-in-loop');
        System.assertEquals(0, preview.slotCount, 'Preview should report no new slots when all starts exist');
        System.assertEquals(16, preview.skippedExisting, 'Preview should count the existing Monday slots as skipped');
        System.assertEquals(0, second.created, 'Second generate should insert nothing');
        System.assertEquals(16, second.skippedExisting, 'Second generate should skip the existing Monday slots');
    }

    @IsTest
    static void saveAndGetSchedulesRoundTripWithHours() {
        Practitioner__c practitioner = insertPractitioner('Drew', 'Patel');

        Test.startTest();
        ScheduleManagementController.ScheduleView created = ScheduleManagementController.saveSchedule(
            null,
            practitioner.Id,
            '  West Wing  ',
            15,
            WEEK_START,
            WEEK_END,
            null,
            weekdayHours('09:00', '12:00')
        );
        ScheduleManagementController.ScheduleView updated = ScheduleManagementController.saveSchedule(
            created.id,
            practitioner.Id,
            'East Wing',
            25,
            WEEK_START.addDays(1),
            WEEK_END,
            false,
            new List<ScheduleManagementController.HoursView>{ hour('1', '10:00', '14:00') }
        );
        List<ScheduleManagementController.ScheduleView> views = ScheduleManagementController.getSchedules(
            practitioner.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, created.id, 'saveSchedule should insert a Schedule__c');
        System.assertEquals('West Wing', created.locationName, 'Create should store location');
        System.assertEquals(5, created.hours.size(), 'Create should store weekday hours');
        System.assertEquals('East Wing', updated.locationName, 'Update should change location');
        System.assertEquals(1, updated.hours.size(), 'Update should replace hours');
        System.assertEquals('1', updated.hours[0].dayOfWeek, 'Updated hours should be Monday only');
        System.assertEquals('10:00', updated.hours[0].startTime, 'Updated start time should persist');
        System.assertEquals(1, views.size(), 'getSchedules should return the provider schedule');
        System.assertEquals(1, views[0].hours.size(), 'getSchedules should include hours');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Schedule_Hours__c WHERE Schedule__c = :updated.id],
            'Only the replaced hours row should remain'
        );
    }

    @IsTest
    static void generateRespectsActiveTimeOff() {
        Practitioner__c practitioner = insertPractitioner('Eli', 'Park');
        Schedule__c schedule = insertScheduleWithHours(practitioner, null, 20, weekdayHours('09:00', '11:00'));
        insert new Schedule_Unavailability__c(
            Practitioner__c = practitioner.Id,
            Schedule__c = schedule.Id,
            Start__c = DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0)),
            End__c = DateTime.newInstance(WEEK_START, Time.newInstance(10, 0, 0, 0)),
            All_Day__c = false,
            Reason__c = 'PTO',
            Active__c = true
        );

        Test.startTest();
        ScheduleManagementController.GenerationResult result = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        Test.stopTest();

        // 09:00–11:00 at 20 minutes = 6 slots; first 3 overlap PTO.
        System.assertEquals(6, result.created, 'All window slots should still be created');
        System.assertEquals(3, result.createdBlocked, 'Overlapping slots should be Blocked');
        System.assertEquals(3, result.createdFree, 'Non-overlapping slots should be Free');
        System.assertEquals(
            3,
            [
                SELECT COUNT()
                FROM Slot__c
                WHERE Schedule__c = :schedule.Id AND Status__c = 'Blocked' AND Block_Reason__c = 'PTO'
            ],
            'Blocked slots should keep the time-off reason'
        );
    }

    @IsTest
    static void applyAndRemoveUnavailability() {
        Practitioner__c practitioner = insertPractitioner('Fay', 'Ortiz');
        Schedule__c schedule = insertScheduleWithHours(practitioner, 'Clinic A', 20, weekdayHours('09:00', '12:00'));
        ScheduleManagementController.generateSlots(schedule.Id, WEEK_START, WEEK_START);

        Datetime startTime = DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0));
        Datetime endTime = DateTime.newInstance(WEEK_START, Time.newInstance(10, 0, 0, 0));

        Test.startTest();
        ScheduleManagementController.UnavailabilityResult applied = ScheduleManagementController.applyUnavailability(
            null,
            practitioner.Id,
            schedule.Id,
            startTime,
            endTime,
            false,
            'Meeting',
            true
        );
        ScheduleManagementController.SlotSummaryView summary = ScheduleManagementController.getSlotSummary(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        List<ScheduleManagementController.UnavailabilityView> upcoming = ScheduleManagementController.getUnavailabilities(
            practitioner.Id,
            schedule.Id
        );
        ScheduleManagementController.UnavailabilityResult removed = ScheduleManagementController.removeUnavailability(
            applied.unavailability.id
        );
        Test.stopTest();

        System.assertEquals(3, applied.slotsBlocked, 'Three Free slots should become Blocked');
        System.assertEquals(0, applied.bookedConflicts, 'No booked conflicts expected');
        System.assertEquals(1, upcoming.size(), 'Upcoming list should include the time off');
        System.assertEquals(3, summary.blockedCount, 'Summary should count blocked slots');
        System.assertEquals(false, removed.unavailability.active, 'Remove should deactivate the row');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Slot__c
                WHERE Schedule__c = :schedule.Id AND Status__c = 'Blocked'
            ],
            'Removing time off should free stamped blocked slots'
        );
    }

    @IsTest
    static void applyUnavailabilityReportsBookedConflicts() {
        Practitioner__c practitioner = insertPractitioner('Gus', 'Lee');
        Patient__c patient = new Patient__c(MRN__c = 'MRN-SCH-CONFLICT', Last_Name__c = 'One');
        insert patient;
        Schedule__c schedule = insertScheduleWithHours(practitioner, null, 20, weekdayHours('09:00', '10:00'));
        ScheduleManagementController.generateSlots(schedule.Id, WEEK_START, WEEK_START);
        Slot__c busy = [
            SELECT Id, Start__c, End__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c ASC
            LIMIT 1
        ];
        busy.Status__c = 'Busy';
        update busy;
        insert new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Slot__c = busy.Id,
            Start__c = busy.Start__c,
            End__c = busy.End__c,
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup'
        );

        Test.startTest();
        ScheduleManagementController.UnavailabilityResult applied = ScheduleManagementController.applyUnavailability(
            null,
            practitioner.Id,
            schedule.Id,
            DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0)),
            DateTime.newInstance(WEEK_START, Time.newInstance(10, 0, 0, 0)),
            false,
            'PTO',
            true
        );
        Test.stopTest();

        System.assertEquals(1, applied.bookedConflicts, 'Busy slots should be reported as conflicts');
        System.assertEquals(
            'Busy',
            [SELECT Status__c FROM Slot__c WHERE Id = :busy.Id].Status__c,
            'Busy slots must not be changed by time off'
        );
    }

    @IsTest
    static void toggleSlotStatusBlocksAndFrees() {
        Schedule__c schedule = insertScheduleWithHours(
            insertPractitioner('Hana', 'Wu'),
            null,
            20,
            weekdayHours('09:00', '10:00')
        );
        ScheduleManagementController.generateSlots(schedule.Id, WEEK_START, WEEK_START);
        Slot__c freeSlot = [
            SELECT Id, Status__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c ASC
            LIMIT 1
        ];
        Slot__c busySlot = [
            SELECT Id, Status__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c DESC
            LIMIT 1
        ];
        busySlot.Status__c = 'Busy';
        update busySlot;

        Test.startTest();
        ScheduleManagementController.SlotView blocked = ScheduleManagementController.toggleSlotStatus(freeSlot.Id);
        ScheduleManagementController.SlotView freed = ScheduleManagementController.toggleSlotStatus(freeSlot.Id);
        Boolean busyThrew = false;
        try {
            ScheduleManagementController.toggleSlotStatus(busySlot.Id);
        } catch (AuraHandledException e) {
            busyThrew = true;
        }
        Test.stopTest();

        System.assertEquals('Blocked', blocked.status, 'Toggle from Free should set Blocked');
        System.assertEquals('Free', freed.status, 'Toggle from Blocked should set Free');
        System.assertEquals(true, busyThrew, 'Busy slots cannot be toggled');
    }

    @IsTest
    static void getSlotsAndValidationErrors() {
        Schedule__c schedule = insertScheduleWithHours(
            insertPractitioner('Ira', 'Moss'),
            null,
            20,
            weekdayHours('09:00', '17:00')
        );
        ScheduleManagementController.generateSlots(schedule.Id, WEEK_START, WEEK_START);
        ScheduleManagementController.maxSlots = 2;

        Test.startTest();
        ScheduleManagementController.SlotListView view = ScheduleManagementController.getSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        ScheduleManagementController.GenerationPreview overLimit = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START.addDays(1),
            WEEK_START.addDays(1),
            null
        );
        Boolean generateThrew = false;
        try {
            ScheduleManagementController.generateSlots(schedule.Id, WEEK_START.addDays(1), WEEK_START.addDays(1));
        } catch (AuraHandledException e) {
            generateThrew = true;
        }

        Boolean missingProvider = threwOnSave(null, 20);
        Boolean badDuration = threwOnSave(schedule.Practitioner__c, 0);
        Boolean durationTooLong = threwOnSave(schedule.Practitioner__c, 1441);
        Boolean noHours = false;
        try {
            ScheduleManagementController.saveSchedule(
                null,
                schedule.Practitioner__c,
                null,
                20,
                WEEK_START,
                WEEK_END,
                true,
                new List<ScheduleManagementController.HoursView>()
            );
        } catch (AuraHandledException e) {
            noHours = true;
        }
        Boolean overlapHours = false;
        try {
            ScheduleManagementController.saveSchedule(
                null,
                schedule.Practitioner__c,
                null,
                20,
                WEEK_START,
                WEEK_END,
                true,
                new List<ScheduleManagementController.HoursView>{
                    hour('1', '09:00', '12:00'),
                    hour('1', '11:00', '13:00')
                }
            );
        } catch (AuraHandledException e) {
            overlapHours = true;
        }
        Boolean badHorizon = false;
        try {
            ScheduleManagementController.saveSchedule(
                null,
                schedule.Practitioner__c,
                null,
                20,
                WEEK_END,
                WEEK_START,
                true,
                weekdayHours('09:00', '17:00')
            );
        } catch (AuraHandledException e) {
            badHorizon = true;
        }
        Boolean missingSchedule = false;
        try {
            ScheduleManagementController.previewSlots(null, WEEK_START, WEEK_END, null);
        } catch (AuraHandledException e) {
            missingSchedule = true;
        }
        Boolean badRange = false;
        try {
            ScheduleManagementController.previewSlots(schedule.Id, WEEK_END, WEEK_START, null);
        } catch (AuraHandledException e) {
            badRange = true;
        }
        Boolean toggleBlank = false;
        try {
            ScheduleManagementController.toggleSlotStatus(null);
        } catch (AuraHandledException e) {
            toggleBlank = true;
        }
        Boolean getSchedulesBlank = false;
        try {
            ScheduleManagementController.getSchedules(null);
        } catch (AuraHandledException e) {
            getSchedulesBlank = true;
        }
        Boolean getSlotsBlank = false;
        try {
            ScheduleManagementController.getSlots(null, WEEK_START, WEEK_END);
        } catch (AuraHandledException e) {
            getSlotsBlank = true;
        }
        Boolean getSummaryBlank = false;
        try {
            ScheduleManagementController.getSlotSummary(null, WEEK_START, WEEK_END);
        } catch (AuraHandledException e) {
            getSummaryBlank = true;
        }
        Boolean unavailBlank = false;
        try {
            ScheduleManagementController.applyUnavailability(
                null,
                null,
                schedule.Id,
                Datetime.now(),
                Datetime.now().addHours(1),
                false,
                'x',
                true
            );
        } catch (AuraHandledException e) {
            unavailBlank = true;
        }
        Boolean removeBlank = false;
        try {
            ScheduleManagementController.removeUnavailability(null);
        } catch (AuraHandledException e) {
            removeBlank = true;
        }
        Test.stopTest();

        System.assertEquals(24, view.slots.size(), 'Monday 09:00–17:00 at 20 minutes should list 24 slots');
        System.assertEquals(false, view.hasMore, '24 slots should not exceed the list limit');
        System.assertEquals(true, overLimit.overLimit, 'Preview should flag counts above the cap');
        System.assertEquals(true, generateThrew, 'Generate should refuse an over-limit plan');
        System.assertEquals(true, missingProvider, 'saveSchedule should require a provider');
        System.assertEquals(true, badDuration, 'Slot duration of 0 should throw');
        System.assertEquals(true, durationTooLong, 'Slot duration over 1440 should throw');
        System.assertEquals(true, noHours, 'Saving without hours should throw');
        System.assertEquals(true, overlapHours, 'Overlapping same-day windows should throw');
        System.assertEquals(true, badHorizon, 'Horizon end before start should throw');
        System.assertEquals(true, missingSchedule, 'Preview without a schedule should throw');
        System.assertEquals(true, badRange, 'Inverted date range should throw');
        System.assertEquals(true, toggleBlank, 'Toggle without a slot Id should throw');
        System.assertEquals(true, getSchedulesBlank, 'getSchedules without a provider should throw');
        System.assertEquals(true, getSlotsBlank, 'getSlots without a schedule should throw');
        System.assertEquals(true, getSummaryBlank, 'getSlotSummary without a schedule should throw');
        System.assertEquals(true, unavailBlank, 'applyUnavailability without a provider should throw');
        System.assertEquals(true, removeBlank, 'removeUnavailability without an Id should throw');
        System.assertEquals(1, ScheduleManagementController.dayOfWeekIndex(WEEK_START), '2026-09-07 should be Monday (1)');
        System.assertEquals(0, ScheduleManagementController.dayOfWeekIndex(Date.newInstance(1900, 1, 7)), 'Epoch Sunday is 0');
    }

    @IsTest
    static void coverageForSummaryAllDayAndGaps() {
        Practitioner__c practitioner = insertPractitioner('Jade', 'Kim');
        Schedule__c schedule = insertScheduleWithHours(practitioner, 'Clinic B', 30, weekdayHours('09:00', '10:00'));
        ScheduleManagementController.generateSlots(schedule.Id, WEEK_START, WEEK_START);
        Slot__c busy = [
            SELECT Id
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c ASC
            LIMIT 1
        ];
        busy.Status__c = 'Busy';
        update busy;

        Schedule__c emptySchedule = insertScheduleWithHours(
            practitioner,
            'Clinic Empty',
            60,
            weekdayHours('09:00', '10:00')
        );

        Test.startTest();
        ScheduleManagementController.SlotSummaryView summary = ScheduleManagementController.getSlotSummary(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        List<ScheduleManagementController.UnavailabilityView> allUpcoming = ScheduleManagementController.getUnavailabilities(
            practitioner.Id,
            null
        );
        ScheduleManagementController.UnavailabilityResult allDay = ScheduleManagementController.applyUnavailability(
            null,
            practitioner.Id,
            schedule.Id,
            DateTime.newInstance(WEEK_START.addDays(1), Time.newInstance(12, 0, 0, 0)),
            DateTime.newInstance(WEEK_START.addDays(1), Time.newInstance(12, 0, 0, 0)),
            true,
            'Holiday',
            true
        );
        ScheduleManagementController.UnavailabilityResult gapFill = ScheduleManagementController.applyUnavailability(
            null,
            practitioner.Id,
            emptySchedule.Id,
            DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0)),
            DateTime.newInstance(WEEK_START, Time.newInstance(10, 0, 0, 0)),
            false,
            'Admin',
            true
        );
        ScheduleManagementController.UnavailabilityResult providerWide = ScheduleManagementController.applyUnavailability(
            null,
            practitioner.Id,
            schedule.Id,
            DateTime.newInstance(WEEK_START.addDays(2), Time.newInstance(9, 0, 0, 0)),
            DateTime.newInstance(WEEK_START.addDays(2), Time.newInstance(10, 0, 0, 0)),
            false,
            'Travel',
            false
        );
        Boolean missingSlot = false;
        try {
            ScheduleManagementController.toggleSlotStatus(busy.Id);
        } catch (AuraHandledException e) {
            // busy already covered; force missing next
        }
        Schedule__c doomed = insertScheduleWithHours(
            insertPractitioner('Gone', 'Row'),
            null,
            20,
            weekdayHours('09:00', '10:00')
        );
        Slot__c doomedSlot = new Slot__c(
            Schedule__c = doomed.Id,
            Start__c = DateTime.newInstance(WEEK_START, Time.newInstance(8, 0, 0, 0)),
            End__c = DateTime.newInstance(WEEK_START, Time.newInstance(8, 20, 0, 0)),
            Status__c = 'Free'
        );
        insert doomedSlot;
        Id doomedSlotId = doomedSlot.Id;
        Id doomedScheduleId = doomed.Id;
        delete doomed;
        try {
            ScheduleManagementController.toggleSlotStatus(doomedSlotId);
        } catch (AuraHandledException e) {
            missingSlot = true;
        }
        Boolean missingSchedule = false;
        try {
            ScheduleManagementController.previewSlots(doomedScheduleId, WEEK_START, WEEK_END, null);
        } catch (AuraHandledException e) {
            missingSchedule = true;
        }
        Boolean noHoursGenerate = false;
        Schedule__c bare = new Schedule__c(
            Practitioner__c = practitioner.Id,
            Slot_Duration_Minutes__c = 20,
            Active__c = true
        );
        insert bare;
        try {
            ScheduleManagementController.generateSlots(bare.Id, WEEK_START, WEEK_START);
        } catch (AuraHandledException e) {
            noHoursGenerate = true;
        }
        Boolean badDay = false;
        try {
            ScheduleManagementController.saveSchedule(
                null,
                practitioner.Id,
                null,
                20,
                WEEK_START,
                WEEK_END,
                true,
                new List<ScheduleManagementController.HoursView>{ hour('9', '09:00', '10:00') }
            );
        } catch (AuraHandledException e) {
            badDay = true;
        }
        Boolean invertedWindow = false;
        try {
            ScheduleManagementController.saveSchedule(
                null,
                practitioner.Id,
                null,
                20,
                WEEK_START,
                WEEK_END,
                true,
                new List<ScheduleManagementController.HoursView>{ hour('1', '17:00', '09:00') }
            );
        } catch (AuraHandledException e) {
            invertedWindow = true;
        }
        Boolean blankUnavailTimes = false;
        try {
            ScheduleManagementController.applyUnavailability(
                null,
                practitioner.Id,
                schedule.Id,
                null,
                null,
                false,
                'x',
                true
            );
        } catch (AuraHandledException e) {
            blankUnavailTimes = true;
        }
        Boolean invertedUnavail = false;
        try {
            ScheduleManagementController.applyUnavailability(
                null,
                practitioner.Id,
                schedule.Id,
                Datetime.now().addHours(2),
                Datetime.now(),
                false,
                'x',
                true
            );
        } catch (AuraHandledException e) {
            invertedUnavail = true;
        }
        Boolean getUnavailBlank = false;
        try {
            ScheduleManagementController.getUnavailabilities(null, null);
        } catch (AuraHandledException e) {
            getUnavailBlank = true;
        }
        Boolean getSlotsDates = false;
        try {
            ScheduleManagementController.getSlots(schedule.Id, null, WEEK_END);
        } catch (AuraHandledException e) {
            getSlotsDates = true;
        }
        ScheduleManagementController.GenerationPreview draftPreview = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            new List<ScheduleManagementController.HoursView>{ hour('1', '14:00', '14:30') }
        );
        Test.stopTest();

        System.assertEquals(1, summary.busyCount, 'Summary should count Busy slots');
        System.assertNotEquals(null, allUpcoming, 'Provider-wide upcoming query should run');
        System.assertEquals(true, allDay.unavailability.allDay, 'All-day time off should be stored');
        System.assertEquals(true, gapFill.slotsCreated > 0, 'Time off on empty schedule should create blocked slots');
        System.assertEquals(true, providerWide.unavailability.scheduleId == null, 'Provider-wide time off leaves Schedule blank');
        System.assertEquals(true, missingSlot, 'Toggle of deleted slot should throw');
        System.assertEquals(true, missingSchedule, 'Preview of deleted schedule should throw');
        System.assertEquals(true, noHoursGenerate, 'Generate without hours should throw');
        System.assertEquals(true, badDay, 'Invalid day of week should throw');
        System.assertEquals(true, invertedWindow, 'Inverted hours window should throw');
        System.assertEquals(true, blankUnavailTimes, 'Blank unavailability times should throw');
        System.assertEquals(true, invertedUnavail, 'Inverted unavailability range should throw');
        System.assertEquals(true, getUnavailBlank, 'getUnavailabilities without provider should throw');
        System.assertEquals(true, getSlotsDates, 'getSlots without dates should throw');
        System.assertEquals(1, draftPreview.slotCount, 'Draft hours preview should use the submitted windows');
    }

    private static Boolean threwOnSave(Id practitionerId, Decimal duration) {
        try {
            ScheduleManagementController.saveSchedule(
                null,
                practitionerId,
                null,
                duration,
                WEEK_START,
                WEEK_END,
                true,
                weekdayHours('09:00', '17:00')
            );
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Datetime weekendSaturday() {
        return DateTime.newInstance(Date.newInstance(2026, 9, 12), Time.newInstance(9, 0, 0, 0));
    }

    private static Datetime weekendSunday() {
        return DateTime.newInstance(Date.newInstance(2026, 9, 13), Time.newInstance(9, 0, 0, 0));
    }

    private static Practitioner__c insertPractitioner(String firstName, String lastName) {
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = firstName, Last_Name__c = lastName);
        insert practitioner;
        return practitioner;
    }

    private static Schedule__c insertScheduleWithHours(
        Practitioner__c practitioner,
        String locationName,
        Integer duration,
        List<ScheduleManagementController.HoursView> hours
    ) {
        ScheduleManagementController.ScheduleView view = ScheduleManagementController.saveSchedule(
            null,
            practitioner.Id,
            locationName,
            duration,
            WEEK_START,
            WEEK_END,
            true,
            hours
        );
        return [SELECT Id, Practitioner__c, Slot_Duration_Minutes__c FROM Schedule__c WHERE Id = :view.id LIMIT 1];
    }

    private static List<ScheduleManagementController.HoursView> weekdayHours(String startTime, String endTime) {
        List<ScheduleManagementController.HoursView> hours = new List<ScheduleManagementController.HoursView>();
        for (Integer day = 1; day <= 5; day++) {
            hours.add(hour(String.valueOf(day), startTime, endTime));
        }
        return hours;
    }

    private static ScheduleManagementController.HoursView hour(String dayOfWeek, String startTime, String endTime) {
        ScheduleManagementController.HoursView row = new ScheduleManagementController.HoursView();
        row.dayOfWeek = dayOfWeek;
        row.startTime = startTime;
        row.endTime = endTime;
        return row;
    }
}
