public with sharing class ScheduleManagementController {
    @TestVisible
    private static Integer maxSlots = 10000;
    @TestVisible
    private static final Integer SLOT_QUERY_LIMIT = 500;
    private static final String STATUS_FREE = 'Free';
    private static final String STATUS_BLOCKED = 'Blocked';
    private static final String STATUS_BUSY = 'Busy';

    public class HoursView {
        @AuraEnabled
        public String dayOfWeek;
        @AuraEnabled
        public String startTime;
        @AuraEnabled
        public String endTime;
    }

    public class ScheduleView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id practitionerId;
        @AuraEnabled
        public String practitionerName;
        @AuraEnabled
        public String locationName;
        @AuraEnabled
        public Decimal slotDurationMinutes;
        @AuraEnabled
        public Date planningHorizonStart;
        @AuraEnabled
        public Date planningHorizonEnd;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public List<HoursView> hours;
    }

    public class SlotView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Datetime startTime;
        @AuraEnabled
        public Datetime endTime;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String blockReason;
        @AuraEnabled
        public Boolean canToggle;
    }

    public class SlotListView {
        @AuraEnabled
        public List<SlotView> slots;
        @AuraEnabled
        public Boolean hasMore;
    }

    public class SlotSummaryView {
        @AuraEnabled
        public Integer freeCount;
        @AuraEnabled
        public Integer blockedCount;
        @AuraEnabled
        public Integer busyCount;
        @AuraEnabled
        public Integer totalCount;
    }

    public class GenerationPreview {
        @AuraEnabled
        public Integer slotCount;
        @AuraEnabled
        public Integer freeCount;
        @AuraEnabled
        public Integer blockedCount;
        @AuraEnabled
        public Datetime firstStart;
        @AuraEnabled
        public Datetime lastEnd;
        @AuraEnabled
        public Integer skippedExisting;
        @AuraEnabled
        public Boolean overLimit;
    }

    public class GenerationResult {
        @AuraEnabled
        public Integer created;
        @AuraEnabled
        public Integer createdFree;
        @AuraEnabled
        public Integer createdBlocked;
        @AuraEnabled
        public Integer skippedExisting;
    }

    public class UnavailabilityView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id practitionerId;
        @AuraEnabled
        public Id scheduleId;
        @AuraEnabled
        public Datetime startTime;
        @AuraEnabled
        public Datetime endTime;
        @AuraEnabled
        public Boolean allDay;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Boolean active;
    }

    public class UnavailabilityResult {
        @AuraEnabled
        public UnavailabilityView unavailability;
        @AuraEnabled
        public Integer slotsBlocked;
        @AuraEnabled
        public Integer slotsCreated;
        @AuraEnabled
        public Integer bookedConflicts;
    }

    @AuraEnabled
    public static List<ScheduleView> getSchedules(Id practitionerId) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }

        List<Schedule__c> rows = [
            SELECT
                Id,
                Name,
                Practitioner__c,
                Practitioner__r.Name,
                Practitioner__r.First_Name__c,
                Practitioner__r.Last_Name__c,
                Location_Name__c,
                Slot_Duration_Minutes__c,
                Planning_Horizon_Start__c,
                Planning_Horizon_End__c,
                Active__c,
                (
                    SELECT Id, Day_Of_Week__c, Start_Time__c, End_Time__c
                    FROM Weekly_Hours__r
                    ORDER BY Day_Of_Week__c ASC, Start_Time__c ASC
                )
            FROM Schedule__c
            WHERE Practitioner__c = :practitionerId
            ORDER BY Active__c DESC, CreatedDate DESC
        ];

        List<ScheduleView> views = new List<ScheduleView>();
        for (Schedule__c row : rows) {
            views.add(toScheduleView(row));
        }
        return views;
    }

    @AuraEnabled
    public static ScheduleView saveSchedule(
        Id scheduleId,
        Id practitionerId,
        String locationName,
        Decimal slotDurationMinutes,
        Date planningHorizonStart,
        Date planningHorizonEnd,
        Boolean active,
        List<HoursView> hours
    ) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }
        Integer duration = toDurationMinutes(slotDurationMinutes);
        validateHorizon(planningHorizonStart, planningHorizonEnd);
        List<HoursView> normalizedHours = normalizeHours(hours);

        Schedule__c schedule;
        if (scheduleId == null) {
            schedule = new Schedule__c();
        } else {
            schedule = querySchedule(scheduleId);
        }

        schedule.Practitioner__c = practitionerId;
        schedule.Location_Name__c = String.isBlank(locationName) ? null : locationName.trim();
        schedule.Slot_Duration_Minutes__c = duration;
        schedule.Planning_Horizon_Start__c = planningHorizonStart;
        schedule.Planning_Horizon_End__c = planningHorizonEnd;
        schedule.Active__c = active == null ? true : active;

        upsert schedule;
        replaceHours(schedule.Id, normalizedHours);
        return toScheduleView(querySchedule(schedule.Id));
    }

    @AuraEnabled
    public static GenerationPreview previewSlots(
        Id scheduleId,
        Date rangeStart,
        Date rangeEnd,
        List<HoursView> hours
    ) {
        SlotPlan plan = buildSlotPlan(scheduleId, rangeStart, rangeEnd, hours);
        return toPreview(plan);
    }

    @AuraEnabled
    public static GenerationResult generateSlots(Id scheduleId, Date rangeStart, Date rangeEnd) {
        SlotPlan plan = buildSlotPlan(scheduleId, rangeStart, rangeEnd, null);
        if (plan.overLimit) {
            throw new AuraHandledException(
                'This range would create more than ' +
                    String.valueOf(maxSlots) +
                    ' slots. Narrow the dates, window, or interval.'
            );
        }
        if (!plan.slots.isEmpty()) {
            insert plan.slots;
        }

        GenerationResult result = new GenerationResult();
        result.created = plan.slots.size();
        result.createdFree = plan.freeCount;
        result.createdBlocked = plan.blockedCount;
        result.skippedExisting = plan.skippedExisting;
        return result;
    }

    @AuraEnabled
    public static SlotListView getSlots(Id scheduleId, Date rangeStart, Date rangeEnd) {
        if (scheduleId == null) {
            throw new AuraHandledException('A schedule is required.');
        }
        validateDateRange(rangeStart, rangeEnd);

        Datetime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        Datetime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        Integer queryLimit = SLOT_QUERY_LIMIT + 1;

        List<Slot__c> rows = [
            SELECT Id, Start__c, End__c, Status__c, Block_Reason__c
            FROM Slot__c
            WHERE Schedule__c = :scheduleId AND Start__c >= :windowStart AND Start__c < :windowEnd
            ORDER BY Start__c ASC
            LIMIT :queryLimit
        ];

        SlotListView view = new SlotListView();
        view.hasMore = rows.size() > SLOT_QUERY_LIMIT;
        view.slots = new List<SlotView>();
        Integer limitSize = Math.min(rows.size(), SLOT_QUERY_LIMIT);
        for (Integer i = 0; i < limitSize; i++) {
            view.slots.add(toSlotView(rows[i]));
        }
        return view;
    }

    @AuraEnabled
    public static SlotSummaryView getSlotSummary(Id scheduleId, Date rangeStart, Date rangeEnd) {
        if (scheduleId == null) {
            throw new AuraHandledException('A schedule is required.');
        }
        validateDateRange(rangeStart, rangeEnd);

        Datetime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        Datetime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        SlotSummaryView summary = new SlotSummaryView();
        summary.freeCount = 0;
        summary.blockedCount = 0;
        summary.busyCount = 0;
        summary.totalCount = 0;

        for (AggregateResult row : [
            SELECT Status__c status, COUNT(Id) cnt
            FROM Slot__c
            WHERE Schedule__c = :scheduleId AND Start__c >= :windowStart AND Start__c < :windowEnd
            GROUP BY Status__c
        ]) {
            String status = (String) row.get('status');
            Integer count = (Integer) row.get('cnt');
            summary.totalCount += count;
            if (status == STATUS_FREE) {
                summary.freeCount = count;
            } else if (status == STATUS_BLOCKED) {
                summary.blockedCount = count;
            } else if (status == STATUS_BUSY) {
                summary.busyCount = count;
            }
        }
        return summary;
    }

    @AuraEnabled
    public static SlotView toggleSlotStatus(Id slotId) {
        if (slotId == null) {
            throw new AuraHandledException('A slot is required.');
        }

        List<Slot__c> rows = [
            SELECT Id, Start__c, End__c, Status__c, Block_Reason__c, Unavailability__c
            FROM Slot__c
            WHERE Id = :slotId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Slot was not found.');
        }

        Slot__c slot = rows[0];
        if (slot.Status__c == STATUS_BUSY) {
            throw new AuraHandledException('Booked slots cannot be blocked or freed.');
        }
        if (slot.Status__c == STATUS_BLOCKED) {
            slot.Status__c = STATUS_FREE;
            slot.Block_Reason__c = null;
            slot.Unavailability__c = null;
        } else {
            slot.Status__c = STATUS_BLOCKED;
            if (String.isBlank(slot.Block_Reason__c)) {
                slot.Block_Reason__c = 'Blocked';
            }
        }
        update slot;
        return toSlotView(slot);
    }

    @AuraEnabled
    public static List<UnavailabilityView> getUnavailabilities(Id practitionerId, Id scheduleId) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }

        Datetime nowValue = Datetime.now().addDays(-1);
        List<Schedule_Unavailability__c> rows;
        if (scheduleId == null) {
            rows = [
                SELECT Id, Practitioner__c, Schedule__c, Start__c, End__c, All_Day__c, Reason__c, Active__c
                FROM Schedule_Unavailability__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND End__c >= :nowValue
                ORDER BY Start__c ASC
                LIMIT 200
            ];
        } else {
            rows = [
                SELECT Id, Practitioner__c, Schedule__c, Start__c, End__c, All_Day__c, Reason__c, Active__c
                FROM Schedule_Unavailability__c
                WHERE
                    Practitioner__c = :practitionerId
                    AND Active__c = TRUE
                    AND End__c >= :nowValue
                    AND (Schedule__c = NULL OR Schedule__c = :scheduleId)
                ORDER BY Start__c ASC
                LIMIT 200
            ];
        }

        List<UnavailabilityView> views = new List<UnavailabilityView>();
        for (Schedule_Unavailability__c row : rows) {
            views.add(toUnavailabilityView(row));
        }
        return views;
    }

    @AuraEnabled
    public static UnavailabilityResult applyUnavailability(
        Id unavailabilityId,
        Id practitionerId,
        Id scheduleId,
        Datetime startTime,
        Datetime endTime,
        Boolean allDay,
        String reason,
        Boolean thisScheduleOnly
    ) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }
        if (startTime == null || endTime == null) {
            throw new AuraHandledException('A start and end are required.');
        }

        Datetime rangeStart = startTime;
        Datetime rangeEnd = endTime;
        if (allDay == true) {
            Date startDate = startTime.date();
            Date endDate = endTime.date();
            rangeStart = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            rangeEnd = DateTime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
        }
        if (rangeEnd <= rangeStart) {
            throw new AuraHandledException('End must be after the start.');
        }

        String trimmedReason = String.isBlank(reason) ? 'Unavailable' : reason.trim();
        Boolean scopeToSchedule = thisScheduleOnly == true && scheduleId != null;

        Schedule_Unavailability__c row;
        if (unavailabilityId == null) {
            row = new Schedule_Unavailability__c();
        } else {
            row = queryUnavailability(unavailabilityId);
        }
        row.Practitioner__c = practitionerId;
        row.Schedule__c = scopeToSchedule ? scheduleId : null;
        row.Start__c = rangeStart;
        row.End__c = rangeEnd;
        row.All_Day__c = allDay == true;
        row.Reason__c = trimmedReason;
        row.Active__c = true;
        upsert row;

        List<Schedule__c> schedules = matchingSchedules(practitionerId, scopeToSchedule ? scheduleId : null);
        Integer slotsBlocked = 0;
        Integer slotsCreated = 0;
        Integer bookedConflicts = 0;

        for (Schedule__c schedule : schedules) {
            UnavailabilityApplyResult applyResult = applyUnavailabilityToSchedule(schedule, row);
            slotsBlocked += applyResult.slotsBlocked;
            slotsCreated += applyResult.slotsCreated;
            bookedConflicts += applyResult.bookedConflicts;
        }

        UnavailabilityResult result = new UnavailabilityResult();
        result.unavailability = toUnavailabilityView(queryUnavailability(row.Id));
        result.slotsBlocked = slotsBlocked;
        result.slotsCreated = slotsCreated;
        result.bookedConflicts = bookedConflicts;
        return result;
    }

    @AuraEnabled
    public static UnavailabilityResult removeUnavailability(Id unavailabilityId) {
        Schedule_Unavailability__c row = queryUnavailability(unavailabilityId);
        row.Active__c = false;
        update row;

        List<Slot__c> stamped = [
            SELECT Id, Status__c, Block_Reason__c, Unavailability__c
            FROM Slot__c
            WHERE Unavailability__c = :row.Id AND Status__c = :STATUS_BLOCKED
        ];
        for (Slot__c slot : stamped) {
            slot.Status__c = STATUS_FREE;
            slot.Block_Reason__c = null;
            slot.Unavailability__c = null;
        }
        if (!stamped.isEmpty()) {
            update stamped;
        }

        UnavailabilityResult result = new UnavailabilityResult();
        result.unavailability = toUnavailabilityView(row);
        result.slotsBlocked = 0;
        result.slotsCreated = 0;
        result.bookedConflicts = 0;
        return result;
    }

    private class SlotPlan {
        public List<Slot__c> slots = new List<Slot__c>();
        public Integer skippedExisting = 0;
        public Integer slotCount = 0;
        public Integer freeCount = 0;
        public Integer blockedCount = 0;
        public Datetime firstStart;
        public Datetime lastEnd;
        public Boolean overLimit = false;
    }

    private class UnavailabilityApplyResult {
        public Integer slotsBlocked = 0;
        public Integer slotsCreated = 0;
        public Integer bookedConflicts = 0;
    }

    private class HoursWindow {
        public Integer dayOfWeek;
        public Time startTime;
        public Time endTime;
    }

    private class UnavailabilityWindow {
        public Datetime startTime;
        public Datetime endTime;
        public String reason;
        public Id unavailabilityId;
    }

    private static SlotPlan buildSlotPlan(Id scheduleId, Date rangeStart, Date rangeEnd, List<HoursView> draftHours) {
        Schedule__c schedule = querySchedule(scheduleId);
        Integer duration = toDurationMinutes(schedule.Slot_Duration_Minutes__c);
        validateDateRange(rangeStart, rangeEnd);

        List<HoursWindow> hours = draftHours != null && !draftHours.isEmpty()
            ? toHoursWindows(normalizeHours(draftHours))
            : loadHoursWindows(schedule.Id);
        if (hours.isEmpty()) {
            throw new AuraHandledException('Add weekly hours before generating slots.');
        }

        Map<Integer, List<HoursWindow>> byDay = new Map<Integer, List<HoursWindow>>();
        for (HoursWindow window : hours) {
            if (!byDay.containsKey(window.dayOfWeek)) {
                byDay.put(window.dayOfWeek, new List<HoursWindow>());
            }
            byDay.get(window.dayOfWeek).add(window);
        }

        Datetime existingFrom = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        Datetime existingTo = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        Set<Long> existingStarts = existingStartKeys(schedule.Id, existingFrom, existingTo);
        List<UnavailabilityWindow> unavailabilities = loadUnavailabilityWindows(
            schedule.Practitioner__c,
            schedule.Id,
            existingFrom,
            existingTo
        );

        SlotPlan plan = new SlotPlan();
        Date day = rangeStart;
        while (day <= rangeEnd) {
            Integer dow = dayOfWeekIndex(day);
            if (byDay.containsKey(dow)) {
                for (HoursWindow window : byDay.get(dow)) {
                    appendDaySlots(
                        plan,
                        schedule.Id,
                        day,
                        window.startTime,
                        window.endTime,
                        duration,
                        existingStarts,
                        unavailabilities
                    );
                }
            }
            day = day.addDays(1);
        }
        plan.overLimit = plan.slotCount > maxSlots;
        return plan;
    }

    private static void appendDaySlots(
        SlotPlan plan,
        Id scheduleId,
        Date day,
        Time windowStart,
        Time windowEnd,
        Integer duration,
        Set<Long> existingStarts,
        List<UnavailabilityWindow> unavailabilities
    ) {
        Datetime cursor = DateTime.newInstance(day, windowStart);
        Datetime dayEnd = DateTime.newInstance(day, windowEnd);
        while (true) {
            Datetime slotEnd = cursor.addMinutes(duration);
            if (slotEnd > dayEnd) {
                break;
            }
            if (existingStarts.contains(cursor.getTime())) {
                plan.skippedExisting++;
            } else {
                plan.slotCount++;
                if (plan.firstStart == null) {
                    plan.firstStart = cursor;
                }
                plan.lastEnd = slotEnd;
                if (plan.slots.size() < maxSlots) {
                    UnavailabilityWindow hit = findOverlappingUnavailability(cursor, slotEnd, unavailabilities);
                    Slot__c slot = new Slot__c(
                        Schedule__c = scheduleId,
                        Start__c = cursor,
                        End__c = slotEnd,
                        Status__c = hit == null ? STATUS_FREE : STATUS_BLOCKED
                    );
                    if (hit != null) {
                        slot.Block_Reason__c = hit.reason;
                        slot.Unavailability__c = hit.unavailabilityId;
                        plan.blockedCount++;
                    } else {
                        plan.freeCount++;
                    }
                    plan.slots.add(slot);
                }
            }
            cursor = slotEnd;
        }
    }

    private static UnavailabilityWindow findOverlappingUnavailability(
        Datetime slotStart,
        Datetime slotEnd,
        List<UnavailabilityWindow> unavailabilities
    ) {
        for (UnavailabilityWindow window : unavailabilities) {
            if (slotStart < window.endTime && slotEnd > window.startTime) {
                return window;
            }
        }
        return null;
    }

    private static UnavailabilityApplyResult applyUnavailabilityToSchedule(
        Schedule__c schedule,
        Schedule_Unavailability__c unavailability
    ) {
        UnavailabilityApplyResult result = new UnavailabilityApplyResult();
        Datetime rangeStart = unavailability.Start__c;
        Datetime rangeEnd = unavailability.End__c;
        Integer duration = toDurationMinutes(schedule.Slot_Duration_Minutes__c);

        List<Slot__c> existing = [
            SELECT Id, Start__c, End__c, Status__c, Block_Reason__c, Unavailability__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id AND Start__c < :rangeEnd AND End__c > :rangeStart
            ORDER BY Start__c ASC
        ];

        List<Slot__c> toUpdate = new List<Slot__c>();
        List<RangePair> occupied = new List<RangePair>();
        for (Slot__c slot : existing) {
            occupied.add(new RangePair(slot.Start__c, slot.End__c));
            if (slot.Status__c == STATUS_BUSY) {
                result.bookedConflicts++;
                continue;
            }
            if (slot.Status__c == STATUS_FREE || slot.Status__c == STATUS_BLOCKED) {
                if (slot.Status__c == STATUS_FREE) {
                    result.slotsBlocked++;
                }
                slot.Status__c = STATUS_BLOCKED;
                slot.Block_Reason__c = unavailability.Reason__c;
                slot.Unavailability__c = unavailability.Id;
                toUpdate.add(slot);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        List<Slot__c> toInsert = new List<Slot__c>();
        Datetime cursor = rangeStart;
        while (cursor < rangeEnd) {
            Datetime slotEnd = cursor.addMinutes(duration);
            if (slotEnd > rangeEnd) {
                break;
            }
            RangePair candidate = new RangePair(cursor, slotEnd);
            if (!overlapsAnyPair(candidate, occupied)) {
                toInsert.add(
                    new Slot__c(
                        Schedule__c = schedule.Id,
                        Start__c = cursor,
                        End__c = slotEnd,
                        Status__c = STATUS_BLOCKED,
                        Block_Reason__c = unavailability.Reason__c,
                        Unavailability__c = unavailability.Id
                    )
                );
                occupied.add(candidate);
            }
            cursor = slotEnd;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            result.slotsCreated = toInsert.size();
        }
        return result;
    }

    private class RangePair {
        public Datetime startTime;
        public Datetime endTime;
        public RangePair(Datetime startTime, Datetime endTime) {
            this.startTime = startTime;
            this.endTime = endTime;
        }
    }

    private static Boolean overlapsAnyPair(RangePair candidate, List<RangePair> occupied) {
        for (RangePair existing : occupied) {
            if (candidate.startTime < existing.endTime && candidate.endTime > existing.startTime) {
                return true;
            }
        }
        return false;
    }

    private static List<Schedule__c> matchingSchedules(Id practitionerId, Id scheduleId) {
        if (scheduleId != null) {
            return [
                SELECT Id, Practitioner__c, Slot_Duration_Minutes__c
                FROM Schedule__c
                WHERE Id = :scheduleId AND Practitioner__c = :practitionerId
                LIMIT 1
            ];
        }
        return [
            SELECT Id, Practitioner__c, Slot_Duration_Minutes__c
            FROM Schedule__c
            WHERE Practitioner__c = :practitionerId AND Active__c = TRUE
        ];
    }

    private static void replaceHours(Id scheduleId, List<HoursView> hours) {
        List<Schedule_Hours__c> existing = [
            SELECT Id
            FROM Schedule_Hours__c
            WHERE Schedule__c = :scheduleId
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }

        List<Schedule_Hours__c> toInsert = new List<Schedule_Hours__c>();
        for (HoursView hour : hours) {
            toInsert.add(
                new Schedule_Hours__c(
                    Schedule__c = scheduleId,
                    Day_Of_Week__c = hour.dayOfWeek,
                    Start_Time__c = parseTime(hour.startTime, 'Start time is required.'),
                    End_Time__c = parseTime(hour.endTime, 'End time is required.')
                )
            );
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static List<HoursView> normalizeHours(List<HoursView> hours) {
        if (hours == null || hours.isEmpty()) {
            throw new AuraHandledException('Add at least one weekly hours window.');
        }

        List<HoursWindow> windows = new List<HoursWindow>();
        for (HoursView hour : hours) {
            if (hour == null || String.isBlank(hour.dayOfWeek)) {
                throw new AuraHandledException('Each hours row needs a day of week.');
            }
            Integer day;
            try {
                day = Integer.valueOf(hour.dayOfWeek.trim());
            } catch (Exception e) {
                throw new AuraHandledException('Days must be values from 0 (Sunday) through 6 (Saturday).');
            }
            if (day < 0 || day > 6) {
                throw new AuraHandledException('Days must be values from 0 (Sunday) through 6 (Saturday).');
            }
            Time startTime = parseTime(hour.startTime, 'Start time is required.');
            Time endTime = parseTime(hour.endTime, 'End time is required.');
            if (endTime <= startTime) {
                throw new AuraHandledException('Each hours window end must be after its start.');
            }
            HoursWindow window = new HoursWindow();
            window.dayOfWeek = day;
            window.startTime = startTime;
            window.endTime = endTime;
            windows.add(window);
        }

        windows.sort(new HoursWindowComparator());
        for (Integer i = 1; i < windows.size(); i++) {
            HoursWindow previous = windows[i - 1];
            HoursWindow current = windows[i];
            if (previous.dayOfWeek == current.dayOfWeek && current.startTime < previous.endTime) {
                throw new AuraHandledException('Weekly hours windows cannot overlap on the same day.');
            }
        }

        List<HoursView> normalized = new List<HoursView>();
        for (HoursWindow window : windows) {
            HoursView view = new HoursView();
            view.dayOfWeek = String.valueOf(window.dayOfWeek);
            view.startTime = formatTime(window.startTime);
            view.endTime = formatTime(window.endTime);
            normalized.add(view);
        }
        return normalized;
    }

    private class HoursWindowComparator implements Comparator<HoursWindow> {
        public Integer compare(HoursWindow a, HoursWindow b) {
            if (a.dayOfWeek != b.dayOfWeek) {
                return a.dayOfWeek < b.dayOfWeek ? -1 : 1;
            }
            if (a.startTime == b.startTime) {
                return 0;
            }
            return a.startTime < b.startTime ? -1 : 1;
        }
    }

    private static List<HoursWindow> toHoursWindows(List<HoursView> hours) {
        List<HoursWindow> windows = new List<HoursWindow>();
        for (HoursView hour : hours) {
            HoursWindow window = new HoursWindow();
            window.dayOfWeek = Integer.valueOf(hour.dayOfWeek);
            window.startTime = parseTime(hour.startTime, 'Start time is required.');
            window.endTime = parseTime(hour.endTime, 'End time is required.');
            windows.add(window);
        }
        return windows;
    }

    private static List<HoursWindow> loadHoursWindows(Id scheduleId) {
        List<HoursWindow> windows = new List<HoursWindow>();
        for (Schedule_Hours__c row : [
            SELECT Day_Of_Week__c, Start_Time__c, End_Time__c
            FROM Schedule_Hours__c
            WHERE Schedule__c = :scheduleId
            ORDER BY Day_Of_Week__c ASC, Start_Time__c ASC
        ]) {
            HoursWindow window = new HoursWindow();
            window.dayOfWeek = Integer.valueOf(row.Day_Of_Week__c);
            window.startTime = row.Start_Time__c;
            window.endTime = row.End_Time__c;
            windows.add(window);
        }
        return windows;
    }

    private static List<UnavailabilityWindow> loadUnavailabilityWindows(
        Id practitionerId,
        Id scheduleId,
        Datetime rangeStart,
        Datetime rangeEnd
    ) {
        List<UnavailabilityWindow> windows = new List<UnavailabilityWindow>();
        for (Schedule_Unavailability__c row : [
            SELECT Id, Start__c, End__c, Reason__c
            FROM Schedule_Unavailability__c
            WHERE
                Practitioner__c = :practitionerId
                AND Active__c = TRUE
                AND Start__c < :rangeEnd
                AND End__c > :rangeStart
                AND (Schedule__c = NULL OR Schedule__c = :scheduleId)
        ]) {
            UnavailabilityWindow window = new UnavailabilityWindow();
            window.startTime = row.Start__c;
            window.endTime = row.End__c;
            window.reason = String.isBlank(row.Reason__c) ? 'Unavailable' : row.Reason__c;
            window.unavailabilityId = row.Id;
            windows.add(window);
        }
        return windows;
    }

    private static Set<Long> existingStartKeys(Id scheduleId, Datetime existingFrom, Datetime existingTo) {
        Set<Long> keys = new Set<Long>();
        for (Slot__c existing : [
            SELECT Start__c
            FROM Slot__c
            WHERE Schedule__c = :scheduleId AND Start__c >= :existingFrom AND Start__c < :existingTo
        ]) {
            if (existing.Start__c != null) {
                keys.add(existing.Start__c.getTime());
            }
        }
        return keys;
    }

    private static Schedule__c querySchedule(Id scheduleId) {
        if (scheduleId == null) {
            throw new AuraHandledException('A schedule is required.');
        }
        List<Schedule__c> rows = [
            SELECT
                Id,
                Name,
                Practitioner__c,
                Practitioner__r.Name,
                Practitioner__r.First_Name__c,
                Practitioner__r.Last_Name__c,
                Location_Name__c,
                Slot_Duration_Minutes__c,
                Planning_Horizon_Start__c,
                Planning_Horizon_End__c,
                Active__c,
                (
                    SELECT Id, Day_Of_Week__c, Start_Time__c, End_Time__c
                    FROM Weekly_Hours__r
                    ORDER BY Day_Of_Week__c ASC, Start_Time__c ASC
                )
            FROM Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Schedule was not found.');
        }
        return rows[0];
    }

    private static Schedule_Unavailability__c queryUnavailability(Id unavailabilityId) {
        if (unavailabilityId == null) {
            throw new AuraHandledException('An unavailability is required.');
        }
        List<Schedule_Unavailability__c> rows = [
            SELECT Id, Practitioner__c, Schedule__c, Start__c, End__c, All_Day__c, Reason__c, Active__c
            FROM Schedule_Unavailability__c
            WHERE Id = :unavailabilityId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Unavailability was not found.');
        }
        return rows[0];
    }

    private static ScheduleView toScheduleView(Schedule__c row) {
        ScheduleView view = new ScheduleView();
        view.id = row.Id;
        view.name = row.Name;
        view.practitionerId = row.Practitioner__c;
        view.practitionerName = practitionerName(row);
        view.locationName = row.Location_Name__c;
        view.slotDurationMinutes = row.Slot_Duration_Minutes__c;
        view.planningHorizonStart = row.Planning_Horizon_Start__c;
        view.planningHorizonEnd = row.Planning_Horizon_End__c;
        view.active = row.Active__c;
        view.hours = new List<HoursView>();
        if (row.Weekly_Hours__r != null) {
            for (Schedule_Hours__c hour : row.Weekly_Hours__r) {
                HoursView hoursView = new HoursView();
                hoursView.dayOfWeek = hour.Day_Of_Week__c;
                hoursView.startTime = formatTime(hour.Start_Time__c);
                hoursView.endTime = formatTime(hour.End_Time__c);
                view.hours.add(hoursView);
            }
        }
        return view;
    }

    private static SlotView toSlotView(Slot__c row) {
        SlotView view = new SlotView();
        view.id = row.Id;
        view.startTime = row.Start__c;
        view.endTime = row.End__c;
        view.status = row.Status__c;
        view.blockReason = row.Block_Reason__c;
        view.canToggle = row.Status__c != STATUS_BUSY;
        return view;
    }

    private static UnavailabilityView toUnavailabilityView(Schedule_Unavailability__c row) {
        UnavailabilityView view = new UnavailabilityView();
        view.id = row.Id;
        view.practitionerId = row.Practitioner__c;
        view.scheduleId = row.Schedule__c;
        view.startTime = row.Start__c;
        view.endTime = row.End__c;
        view.allDay = row.All_Day__c;
        view.reason = row.Reason__c;
        view.active = row.Active__c;
        return view;
    }

    private static GenerationPreview toPreview(SlotPlan plan) {
        GenerationPreview preview = new GenerationPreview();
        preview.slotCount = plan.slotCount;
        preview.freeCount = plan.freeCount;
        preview.blockedCount = plan.blockedCount;
        preview.firstStart = plan.firstStart;
        preview.lastEnd = plan.lastEnd;
        preview.skippedExisting = plan.skippedExisting;
        preview.overLimit = plan.overLimit;
        return preview;
    }

    private static String practitionerName(Schedule__c row) {
        if (row.Practitioner__r == null) {
            return '';
        }
        if (String.isNotBlank(row.Practitioner__r.Name)) {
            return row.Practitioner__r.Name;
        }
        String first = row.Practitioner__r.First_Name__c == null ? '' : row.Practitioner__r.First_Name__c;
        String last = row.Practitioner__r.Last_Name__c == null ? '' : row.Practitioner__r.Last_Name__c;
        return (first + ' ' + last).trim();
    }

    private static Integer toDurationMinutes(Decimal slotDurationMinutes) {
        if (slotDurationMinutes == null || slotDurationMinutes <= 0) {
            throw new AuraHandledException('Slot duration must be a positive number of minutes.');
        }
        Integer duration = slotDurationMinutes.intValue();
        if (duration > 1440) {
            throw new AuraHandledException('Slot duration cannot exceed 1440 minutes.');
        }
        return duration;
    }

    private static void validateHorizon(Date planningHorizonStart, Date planningHorizonEnd) {
        if (planningHorizonStart != null && planningHorizonEnd != null && planningHorizonEnd < planningHorizonStart) {
            throw new AuraHandledException('Planning horizon end must be on or after the start date.');
        }
    }

    private static void validateDateRange(Date rangeStart, Date rangeEnd) {
        if (rangeStart == null || rangeEnd == null) {
            throw new AuraHandledException('A start date and end date are required.');
        }
        if (rangeEnd < rangeStart) {
            throw new AuraHandledException('End date must be on or after the start date.');
        }
    }

    private static Time parseTime(String value, String blankMessage) {
        if (String.isBlank(value)) {
            throw new AuraHandledException(blankMessage);
        }
        String trimmed = value.trim();
        if (trimmed.endsWith('Z') || trimmed.endsWith('z')) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        List<String> parts = trimmed.split(':');
        if (parts.size() < 2) {
            throw new AuraHandledException('Enter times as HH:mm.');
        }
        try {
            Integer hour = Integer.valueOf(parts[0]);
            Integer minute = Integer.valueOf(parts[1]);
            Integer second = 0;
            if (parts.size() > 2) {
                String secondPart = parts[2];
                Integer dot = secondPart.indexOf('.');
                if (dot >= 0) {
                    secondPart = secondPart.substring(0, dot);
                }
                if (String.isNotBlank(secondPart)) {
                    second = Integer.valueOf(secondPart);
                }
            }
            if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
                throw new AuraHandledException('Enter a valid time of day.');
            }
            return Time.newInstance(hour, minute, second, 0);
        } catch (TypeException e) {
            throw new AuraHandledException('Enter times as HH:mm.');
        }
    }

    private static String formatTime(Time value) {
        if (value == null) {
            return null;
        }
        String hour = value.hour() < 10 ? '0' + String.valueOf(value.hour()) : String.valueOf(value.hour());
        String minute = value.minute() < 10 ? '0' + String.valueOf(value.minute()) : String.valueOf(value.minute());
        return hour + ':' + minute;
    }

    // 1900-01-07 was a Sunday. 0 = Sunday ... 6 = Saturday.
    @TestVisible
    private static Integer dayOfWeekIndex(Date day) {
        Integer raw = Date.newInstance(1900, 1, 7).daysBetween(day);
        Integer index = Math.mod(raw, 7);
        return index < 0 ? index + 7 : index;
    }
}
