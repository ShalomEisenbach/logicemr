public with sharing class ScheduleManagementController {
    @TestVisible
    private static Integer maxSlots = 10000;
    @TestVisible
    private static final Integer SLOT_QUERY_LIMIT = 500;
    private static final String STATUS_FREE = 'Free';
    private static final String STATUS_BLOCKED = 'Blocked';
    private static final String STATUS_BUSY = 'Busy';

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
        public Boolean canToggle;
    }

    public class SlotListView {
        @AuraEnabled
        public List<SlotView> slots;
        @AuraEnabled
        public Boolean hasMore;
    }

    public class GenerationPreview {
        @AuraEnabled
        public Integer slotCount;
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
        public Integer skippedExisting;
    }

    @AuraEnabled
    public static List<ScheduleView> getSchedules(Id practitionerId) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }

        List<ScheduleView> views = new List<ScheduleView>();
        for (Schedule__c row : [
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
                Active__c
            FROM Schedule__c
            WHERE Practitioner__c = :practitionerId
            ORDER BY Active__c DESC, CreatedDate DESC
        ]) {
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
        Boolean active
    ) {
        if (practitionerId == null) {
            throw new AuraHandledException('A provider is required.');
        }
        Integer duration = toDurationMinutes(slotDurationMinutes);
        validateHorizon(planningHorizonStart, planningHorizonEnd);

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
        return toScheduleView(querySchedule(schedule.Id));
    }

    @AuraEnabled
    public static GenerationPreview previewSlots(
        Id scheduleId,
        Date rangeStart,
        Date rangeEnd,
        String dailyStart,
        String dailyEnd,
        List<Integer> includedDays
    ) {
        SlotPlan plan = buildSlotPlan(scheduleId, rangeStart, rangeEnd, dailyStart, dailyEnd, includedDays);
        return toPreview(plan);
    }

    @AuraEnabled
    public static GenerationResult generateSlots(
        Id scheduleId,
        Date rangeStart,
        Date rangeEnd,
        String dailyStart,
        String dailyEnd,
        List<Integer> includedDays
    ) {
        SlotPlan plan = buildSlotPlan(scheduleId, rangeStart, rangeEnd, dailyStart, dailyEnd, includedDays);
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
            SELECT Id, Start__c, End__c, Status__c
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
    public static SlotView toggleSlotStatus(Id slotId) {
        if (slotId == null) {
            throw new AuraHandledException('A slot is required.');
        }

        List<Slot__c> rows = [
            SELECT Id, Start__c, End__c, Status__c
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
        slot.Status__c = slot.Status__c == STATUS_BLOCKED ? STATUS_FREE : STATUS_BLOCKED;
        update slot;
        return toSlotView(slot);
    }

    private class SlotPlan {
        public List<Slot__c> slots = new List<Slot__c>();
        public Integer skippedExisting = 0;
        public Integer slotCount = 0;
        public Datetime firstStart;
        public Datetime lastEnd;
        public Boolean overLimit = false;
    }

    private static SlotPlan buildSlotPlan(
        Id scheduleId,
        Date rangeStart,
        Date rangeEnd,
        String dailyStart,
        String dailyEnd,
        List<Integer> includedDays
    ) {
        Schedule__c schedule = querySchedule(scheduleId);
        Integer duration = toDurationMinutes(schedule.Slot_Duration_Minutes__c);
        validateDateRange(rangeStart, rangeEnd);
        Time windowStart = parseTime(dailyStart, 'Daily start time is required.');
        Time windowEnd = parseTime(dailyEnd, 'Daily end time is required.');
        if (windowEnd <= windowStart) {
            throw new AuraHandledException('Daily end time must be after the start time.');
        }
        Set<Integer> days = normalizeDays(includedDays);

        Datetime existingFrom = DateTime.newInstance(rangeStart, windowStart);
        Datetime existingTo = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        Set<Long> existingStarts = existingStartKeys(schedule.Id, existingFrom, existingTo);

        SlotPlan plan = new SlotPlan();
        Date day = rangeStart;
        while (day <= rangeEnd) {
            if (days.contains(dayOfWeekIndex(day))) {
                appendDaySlots(plan, schedule.Id, day, windowStart, windowEnd, duration, existingStarts);
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
        Set<Long> existingStarts
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
                    plan.slots.add(
                        new Slot__c(
                            Schedule__c = scheduleId,
                            Start__c = cursor,
                            End__c = slotEnd,
                            Status__c = STATUS_FREE
                        )
                    );
                }
            }
            cursor = slotEnd;
        }
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
                Active__c
            FROM Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Schedule was not found.');
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
        return view;
    }

    private static SlotView toSlotView(Slot__c row) {
        SlotView view = new SlotView();
        view.id = row.Id;
        view.startTime = row.Start__c;
        view.endTime = row.End__c;
        view.status = row.Status__c;
        view.canToggle = row.Status__c != STATUS_BUSY;
        return view;
    }

    private static GenerationPreview toPreview(SlotPlan plan) {
        GenerationPreview preview = new GenerationPreview();
        preview.slotCount = plan.slotCount;
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

    private static Set<Integer> normalizeDays(List<Integer> includedDays) {
        if (includedDays == null || includedDays.isEmpty()) {
            throw new AuraHandledException('Select at least one day of the week.');
        }
        Set<Integer> days = new Set<Integer>();
        for (Integer day : includedDays) {
            if (day == null || day < 0 || day > 6) {
                throw new AuraHandledException('Days must be values from 0 (Sunday) through 6 (Saturday).');
            }
            days.add(day);
        }
        return days;
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

    // 1900-01-07 was a Sunday. 0 = Sunday ... 6 = Saturday.
    @TestVisible
    private static Integer dayOfWeekIndex(Date day) {
        Integer raw = Date.newInstance(1900, 1, 7).daysBetween(day);
        Integer index = Math.mod(raw, 7);
        return index < 0 ? index + 7 : index;
    }
}
