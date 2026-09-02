@IsTest
private class ScheduleManagementControllerTest {
    private static final Date WEEK_START = Date.newInstance(2026, 9, 7);
    private static final Date WEEK_END = Date.newInstance(2026, 9, 13);
    private static final List<Integer> WEEKDAYS = new List<Integer>{ 1, 2, 3, 4, 5 };
    private static final String DAILY_START = '09:00';
    private static final String DAILY_END = '17:00';

    @IsTest
    static void generateSlotsCreatesExpectedCountAndTimes() {
        Schedule__c schedule = insertSchedule(insertPractitioner('Ada', 'Lopez'), 'Clinic A', 20);

        Test.startTest();
        ScheduleManagementController.GenerationPreview preview = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_END,
            DAILY_START,
            DAILY_END,
            WEEKDAYS
        );
        ScheduleManagementController.GenerationResult result = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_END,
            DAILY_START,
            DAILY_END,
            WEEKDAYS
        );
        Test.stopTest();

        // Mon–Fri, 09:00–17:00, 20-minute interval = 5 days × 24 slots.
        System.assertEquals(120, preview.slotCount, 'Preview should report 120 weekday slots');
        System.assertEquals(false, preview.overLimit, '120 slots should be under the generation cap');
        System.assertEquals(0, preview.skippedExisting, 'No existing slots should be skipped on first preview');
        System.assertEquals(120, result.created, 'Generate should insert the previewed slot count');
        System.assertEquals(0, result.skippedExisting, 'No existing slots should be skipped on first generate');

        List<Slot__c> slots = [
            SELECT Start__c, End__c, Status__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id
            ORDER BY Start__c ASC
        ];
        System.assertEquals(120, slots.size(), 'Exactly 120 Slot__c rows should exist');

        Datetime expectedFirstStart = DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0));
        Datetime expectedFirstEnd = expectedFirstStart.addMinutes(20);
        Datetime expectedLastStart = DateTime.newInstance(Date.newInstance(2026, 9, 11), Time.newInstance(16, 40, 0, 0));
        Datetime expectedLastEnd = expectedLastStart.addMinutes(20);

        System.assertEquals(expectedFirstStart, preview.firstStart, 'Preview first start should be Monday 09:00');
        System.assertEquals(expectedLastEnd, preview.lastEnd, 'Preview last end should be Friday 17:00');
        System.assertEquals(expectedFirstStart, slots[0].Start__c, 'First slot should start Monday 09:00');
        System.assertEquals(expectedFirstEnd, slots[0].End__c, 'First slot should end Monday 09:20');
        System.assertEquals('Free', slots[0].Status__c, 'Generated slots should be Free');
        System.assertEquals(expectedLastStart, slots[119].Start__c, 'Last slot should start Friday 16:40');
        System.assertEquals(expectedLastEnd, slots[119].End__c, 'Last slot should end Friday 17:00');

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Slot__c
                WHERE Schedule__c = :schedule.Id AND (Start__c = :weekendSaturday() OR Start__c = :weekendSunday())
            ],
            'Weekend days should be skipped when only weekdays are included'
        );
    }

    @IsTest
    static void generateSlotsIsBulkAndSkipsExisting() {
        Schedule__c schedule = insertSchedule(insertPractitioner('Ben', 'Ng'), null, 30);

        Test.startTest();
        ScheduleManagementController.GenerationResult first = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            '09:00:00.000Z',
            DAILY_END,
            new List<Integer>{ 1 }
        );
        Integer dmlAfterInsert = Limits.getDmlStatements();
        ScheduleManagementController.GenerationPreview preview = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            DAILY_START,
            DAILY_END,
            new List<Integer>{ 1 }
        );
        ScheduleManagementController.GenerationResult second = ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            DAILY_START,
            DAILY_END,
            new List<Integer>{ 1 }
        );
        Test.stopTest();

        // Monday 09:00–17:00 at 30 minutes = 16 slots.
        System.assertEquals(16, first.created, 'First generate inserts 16 slots');
        System.assertEquals(
            16,
            [SELECT COUNT() FROM Slot__c WHERE Schedule__c = :schedule.Id],
            'First generate inserts 16 Slot__c rows'
        );
        System.assertEquals(1, dmlAfterInsert, 'Slot generation must use one bulk insert, not insert-in-loop');
        System.assertEquals(0, preview.slotCount, 'Preview should report no new slots when all starts exist');
        System.assertEquals(16, preview.skippedExisting, 'Preview should count the existing Monday slots as skipped');
        System.assertEquals(0, second.created, 'Second generate should insert nothing');
        System.assertEquals(16, second.skippedExisting, 'Second generate should skip the existing Monday slots');
    }

    @IsTest
    static void saveAndGetSchedulesRoundTrip() {
        Practitioner__c practitioner = insertPractitioner('Cara', 'Singh');

        Test.startTest();
        ScheduleManagementController.ScheduleView created = ScheduleManagementController.saveSchedule(
            null,
            practitioner.Id,
            '  West Wing  ',
            15,
            WEEK_START,
            WEEK_END,
            null
        );
        ScheduleManagementController.ScheduleView updated = ScheduleManagementController.saveSchedule(
            created.id,
            practitioner.Id,
            'East Wing',
            25,
            WEEK_START.addDays(1),
            WEEK_END,
            false
        );
        List<ScheduleManagementController.ScheduleView> views = ScheduleManagementController.getSchedules(
            practitioner.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, created.id, 'saveSchedule should insert a Schedule__c');
        System.assertEquals('West Wing', created.locationName, 'Create should store location');
        System.assertEquals(15, created.slotDurationMinutes, 'Create should store slot duration');
        System.assertEquals(WEEK_START, created.planningHorizonStart, 'Create should store horizon start');
        System.assertEquals(WEEK_END, created.planningHorizonEnd, 'Create should store horizon end');
        System.assertEquals(true, created.active, 'Create should store Active');
        System.assertEquals('East Wing', updated.locationName, 'Update should change location');
        System.assertEquals(25, updated.slotDurationMinutes, 'Update should change duration');
        System.assertEquals(false, updated.active, 'Update should change Active');
        System.assertEquals(1, views.size(), 'getSchedules should return the provider schedule');
        System.assertEquals(updated.id, views[0].id, 'getSchedules should return the saved schedule');
    }

    @IsTest
    static void toggleSlotStatusBlocksAndFrees() {
        Schedule__c schedule = insertSchedule(insertPractitioner('Drew', 'Patel'), null, 20);
        ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            '09:00',
            '10:00',
            new List<Integer>{ 1 }
        );
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
    static void getSlotsReturnsWindowAndHasMore() {
        Schedule__c schedule = insertSchedule(insertPractitioner('Eli', 'Park'), null, 20);
        ScheduleManagementController.generateSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            DAILY_START,
            DAILY_END,
            new List<Integer>{ 1 }
        );

        Test.startTest();
        ScheduleManagementController.SlotListView view = ScheduleManagementController.getSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START
        );
        Test.stopTest();

        System.assertEquals(24, view.slots.size(), 'Monday 09:00–17:00 at 20 minutes should list 24 slots');
        System.assertEquals(false, view.hasMore, '24 slots should not exceed the list limit');
        System.assertEquals(true, view.slots[0].canToggle, 'Free slots can be toggled');
        System.assertEquals(
            DateTime.newInstance(WEEK_START, Time.newInstance(9, 0, 0, 0)),
            view.slots[0].startTime,
            'Listed first start should match the generated window'
        );
    }

    @IsTest
    static void previewOverLimitAndValidationErrors() {
        Schedule__c schedule = insertSchedule(insertPractitioner('Fay', 'Ortiz'), null, 20);
        ScheduleManagementController.maxSlots = 2;

        Test.startTest();
        ScheduleManagementController.GenerationPreview overLimit = ScheduleManagementController.previewSlots(
            schedule.Id,
            WEEK_START,
            WEEK_START,
            DAILY_START,
            DAILY_END,
            new List<Integer>{ 1 }
        );
        Boolean generateThrew = false;
        try {
            ScheduleManagementController.generateSlots(
                schedule.Id,
                WEEK_START,
                WEEK_START,
                DAILY_START,
                DAILY_END,
                new List<Integer>{ 1 }
            );
        } catch (AuraHandledException e) {
            generateThrew = true;
        }

        Boolean missingProvider = threwOnSave(null, 20);
        Boolean badDuration = threwOnSave(schedule.Practitioner__c, 0);
        Boolean durationTooLong = threwOnSave(schedule.Practitioner__c, 1441);
        Schedule__c orphan = insertSchedule(insertPractitioner('Gone', 'Row'), null, 20);
        insert new Slot__c(
            Schedule__c = orphan.Id,
            Start__c = DateTime.newInstance(WEEK_START, Time.newInstance(8, 0, 0, 0)),
            End__c = DateTime.newInstance(WEEK_START, Time.newInstance(8, 20, 0, 0)),
            Status__c = 'Free'
        );
        Id missingSlotId = [SELECT Id FROM Slot__c WHERE Schedule__c = :orphan.Id LIMIT 1].Id;
        Id missingScheduleId = orphan.Id;
        delete orphan;

        Boolean missingSlot = false;
        try {
            ScheduleManagementController.toggleSlotStatus(missingSlotId);
        } catch (AuraHandledException e) {
            missingSlot = true;
        }
        Boolean missingScheduleRecord = false;
        try {
            ScheduleManagementController.previewSlots(
                missingScheduleId,
                WEEK_START,
                WEEK_END,
                DAILY_START,
                DAILY_END,
                WEEKDAYS
            );
        } catch (AuraHandledException e) {
            missingScheduleRecord = true;
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
                true
            );
        } catch (AuraHandledException e) {
            badHorizon = true;
        }
        Boolean missingSchedule = false;
        try {
            ScheduleManagementController.previewSlots(null, WEEK_START, WEEK_END, DAILY_START, DAILY_END, WEEKDAYS);
        } catch (AuraHandledException e) {
            missingSchedule = true;
        }
        Boolean badRange = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_END,
                WEEK_START,
                DAILY_START,
                DAILY_END,
                WEEKDAYS
            );
        } catch (AuraHandledException e) {
            badRange = true;
        }
        Boolean badWindow = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                DAILY_END,
                DAILY_START,
                WEEKDAYS
            );
        } catch (AuraHandledException e) {
            badWindow = true;
        }
        Boolean noDays = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                DAILY_START,
                DAILY_END,
                new List<Integer>()
            );
        } catch (AuraHandledException e) {
            noDays = true;
        }
        Boolean badDay = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                DAILY_START,
                DAILY_END,
                new List<Integer>{ 8 }
            );
        } catch (AuraHandledException e) {
            badDay = true;
        }
        Boolean blankTime = false;
        try {
            ScheduleManagementController.previewSlots(schedule.Id, WEEK_START, WEEK_END, null, DAILY_END, WEEKDAYS);
        } catch (AuraHandledException e) {
            blankTime = true;
        }
        Boolean badTime = false;
        try {
            ScheduleManagementController.previewSlots(schedule.Id, WEEK_START, WEEK_END, 'morning', DAILY_END, WEEKDAYS);
        } catch (AuraHandledException e) {
            badTime = true;
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
        Boolean getSlotsDates = false;
        try {
            ScheduleManagementController.getSlots(schedule.Id, null, WEEK_END);
        } catch (AuraHandledException e) {
            getSlotsDates = true;
        }
        Boolean nullDays = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                DAILY_START,
                DAILY_END,
                null
            );
        } catch (AuraHandledException e) {
            nullDays = true;
        }
        Boolean invalidHour = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                '25:00',
                DAILY_END,
                WEEKDAYS
            );
        } catch (AuraHandledException e) {
            invalidHour = true;
        }
        Boolean shortTime = false;
        try {
            ScheduleManagementController.previewSlots(
                schedule.Id,
                WEEK_START,
                WEEK_END,
                '09',
                DAILY_END,
                WEEKDAYS
            );
        } catch (AuraHandledException e) {
            shortTime = true;
        }
        Test.stopTest();

        System.assertEquals(24, overLimit.slotCount, 'Preview should still report the full slot count');
        System.assertEquals(true, overLimit.overLimit, 'Preview should flag counts above the cap');
        System.assertEquals(true, generateThrew, 'Generate should refuse an over-limit plan');
        System.assertEquals(true, missingProvider, 'saveSchedule should require a provider');
        System.assertEquals(true, badDuration, 'Slot duration of 0 should throw');
        System.assertEquals(true, durationTooLong, 'Slot duration over 1440 should throw');
        System.assertEquals(true, missingSlot, 'Toggle of an unknown Id should throw');
        System.assertEquals(true, missingScheduleRecord, 'Preview of an unknown schedule Id should throw');
        System.assertEquals(true, badHorizon, 'Horizon end before start should throw');
        System.assertEquals(true, missingSchedule, 'Preview without a schedule should throw');
        System.assertEquals(true, badRange, 'Inverted date range should throw');
        System.assertEquals(true, badWindow, 'End time before start time should throw');
        System.assertEquals(true, noDays, 'No selected days should throw');
        System.assertEquals(true, badDay, 'Day values outside 0–6 should throw');
        System.assertEquals(true, blankTime, 'Blank daily start should throw');
        System.assertEquals(true, badTime, 'Unparseable time should throw');
        System.assertEquals(true, toggleBlank, 'Toggle without a slot Id should throw');
        System.assertEquals(true, getSchedulesBlank, 'getSchedules without a provider should throw');
        System.assertEquals(true, getSlotsBlank, 'getSlots without a schedule should throw');
        System.assertEquals(true, getSlotsDates, 'getSlots without dates should throw');
        System.assertEquals(true, nullDays, 'Null included days should throw');
        System.assertEquals(true, invalidHour, 'Hour 25 should throw');
        System.assertEquals(true, shortTime, 'Time without minutes should throw');
        System.assertEquals(0, [SELECT COUNT() FROM Slot__c WHERE Schedule__c = :schedule.Id], 'Over-limit generate must not insert');
        System.assertEquals(1, ScheduleManagementController.dayOfWeekIndex(WEEK_START), '2026-09-07 should be Monday (1)');
        System.assertEquals(0, ScheduleManagementController.dayOfWeekIndex(Date.newInstance(1900, 1, 7)), 'Epoch Sunday is 0');
        System.assertEquals(
            6,
            ScheduleManagementController.dayOfWeekIndex(Date.newInstance(1900, 1, 6)),
            'Date before the Sunday epoch should wrap to Saturday (6)'
        );
    }

    private static Boolean threwOnSave(Id practitionerId, Decimal duration) {
        try {
            ScheduleManagementController.saveSchedule(null, practitionerId, null, duration, WEEK_START, WEEK_END, true);
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

    private static Schedule__c insertSchedule(Practitioner__c practitioner, String locationName, Integer duration) {
        Schedule__c schedule = new Schedule__c(
            Practitioner__c = practitioner.Id,
            Location_Name__c = locationName,
            Slot_Duration_Minutes__c = duration,
            Planning_Horizon_Start__c = WEEK_START,
            Planning_Horizon_End__c = WEEK_END,
            Active__c = true
        );
        insert schedule;
        return schedule;
    }
}
