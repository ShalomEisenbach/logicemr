public with sharing class AppointmentCalendarController {
    private static final String SLOT_FREE = 'Free';
    private static final String SLOT_BUSY = 'Busy';
    private static final String APPT_BOOKED = 'Booked';
    private static final String APPT_CANCELLED = 'Cancelled';
    private static final String APPT_NO_SHOW = 'No Show';
    private static final String APPT_ARRIVED = 'Arrived';
    private static final String ENC_ARRIVED = 'Arrived';
    private static final String ENC_CLASS_DEFAULT = 'Outpatient';
    private static final String ENC_CLASS_EMERGENCY = 'Emergency';
    private static final Integer SLOT_QUERY_LIMIT = 400;
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Proposed', 'Booked' };
    @TestVisible
    private static final Set<String> APPOINTMENT_TYPES = new Set<String>{
        'Checkup',
        'Emergency',
        'Follow-up',
        'Routine',
        'Walk-in'
    };

    public class AppointmentView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String appointmentType;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Id patientId;
        @AuraEnabled
        public String patientName;
        @AuraEnabled
        public Id encounterId;
        @AuraEnabled
        public String encounterName;
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
        public String appointmentType;
        @AuraEnabled
        public String locationName;
        @AuraEnabled
        public Id practitionerId;
        @AuraEnabled
        public String practitionerName;
        @AuraEnabled
        public Id scheduleId;
        @AuraEnabled
        public Integer durationMinutes;
        @AuraEnabled
        public AppointmentView appointment;
    }

    public class GridView {
        @AuraEnabled
        public List<SlotView> slots;
        @AuraEnabled
        public Boolean hasMore;
        @AuraEnabled
        public Integer slotDurationMinutes;
        @AuraEnabled
        public Id defaultScheduleId;
    }

    public class ScheduleOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String locationName;
        @AuraEnabled
        public Integer slotDurationMinutes;
        @AuraEnabled
        public Boolean active;
    }

    public class ActionResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Appointment__c appointment;
        @AuraEnabled
        public Id freedSlotId;
        @AuraEnabled
        public Id busiedSlotId;
        @AuraEnabled
        public Id appointmentId;
        @AuraEnabled
        public String appointmentName;
        @AuraEnabled
        public String appointmentStatus;
        @AuraEnabled
        public Id slotId;
        @AuraEnabled
        public String slotStatus;
        @AuraEnabled
        public Id previousSlotId;
        @AuraEnabled
        public String previousSlotStatus;
        @AuraEnabled
        public Id encounterId;
        @AuraEnabled
        public String encounterName;
    }

    public class SlotRange {
        @AuraEnabled
        public Datetime startTime { get; set; }
        @AuraEnabled
        public Datetime endTime { get; set; }
    }

    public class AdHocSlotResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public List<Slot__c> slots;
        @AuraEnabled
        public Integer created;
        @AuraEnabled
        public Integer skipped;
    }

    @AuraEnabled
    public static List<String> getLocations(Id practitionerId) {
        List<String> locations = new List<String>();
        List<AggregateResult> rows;
        if (practitionerId == null) {
            rows = [
                SELECT Location_Name__c locationName
                FROM Schedule__c
                WHERE Active__c = TRUE AND Location_Name__c != NULL
                GROUP BY Location_Name__c
                ORDER BY Location_Name__c
            ];
        } else {
            rows = [
                SELECT Location_Name__c locationName
                FROM Schedule__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND Location_Name__c != NULL
                GROUP BY Location_Name__c
                ORDER BY Location_Name__c
            ];
        }
        for (AggregateResult row : rows) {
            String locationName = (String) row.get('locationName');
            if (String.isNotBlank(locationName)) {
                locations.add(locationName);
            }
        }
        return locations;
    }

    @AuraEnabled
    public static GridView getGrid(Id practitionerId, String locationName, Date rangeStart, Date rangeEnd) {
        if (practitionerId == null && String.isBlank(locationName)) {
            throw error('Select a provider or a location.');
        }
        if (rangeStart == null || rangeEnd == null) {
            throw error('A start date and end date are required.');
        }
        if (rangeEnd < rangeStart) {
            throw error('End date must be on or after the start date.');
        }

        Datetime windowStart = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        Datetime windowEnd = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        Integer queryLimit = SLOT_QUERY_LIMIT + 1;
        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;

        List<Slot__c> rows = querySlots(practitionerId, filterLocation, locationFilter, windowStart, windowEnd, queryLimit);

        GridView view = new GridView();
        view.hasMore = rows.size() > SLOT_QUERY_LIMIT;
        view.slots = new List<SlotView>();
        Integer limitSize = Math.min(rows.size(), SLOT_QUERY_LIMIT);
        Integer durationMinutes = 20;
        for (Integer i = 0; i < limitSize; i++) {
            SlotView slotView = toSlotView(rows[i]);
            view.slots.add(slotView);
            if (rows[i].Schedule__r != null && rows[i].Schedule__r.Slot_Duration_Minutes__c != null) {
                durationMinutes = Integer.valueOf(rows[i].Schedule__r.Slot_Duration_Minutes__c);
            }
        }
        view.slotDurationMinutes = durationMinutes;
        view.defaultScheduleId = limitSize > 0 ? rows[0].Schedule__c : null;
        return view;
    }

    @AuraEnabled
    public static List<ScheduleOption> getActiveSchedules(Id practitionerId, String locationName) {
        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;
        List<Schedule__c> rows;
        if (practitionerId != null && filterLocation) {
            rows = [
                SELECT Id, Name, Location_Name__c, Slot_Duration_Minutes__c, Active__c
                FROM Schedule__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND Location_Name__c = :locationFilter
                ORDER BY Location_Name__c NULLS LAST, CreatedDate DESC
            ];
        } else if (practitionerId != null) {
            rows = [
                SELECT Id, Name, Location_Name__c, Slot_Duration_Minutes__c, Active__c
                FROM Schedule__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE
                ORDER BY Location_Name__c NULLS LAST, CreatedDate DESC
            ];
        } else if (filterLocation) {
            rows = [
                SELECT Id, Name, Location_Name__c, Slot_Duration_Minutes__c, Active__c
                FROM Schedule__c
                WHERE Active__c = TRUE AND Location_Name__c = :locationFilter
                ORDER BY Location_Name__c NULLS LAST, CreatedDate DESC
            ];
        } else {
            return new List<ScheduleOption>();
        }

        List<ScheduleOption> options = new List<ScheduleOption>();
        for (Schedule__c row : rows) {
            ScheduleOption option = new ScheduleOption();
            option.id = row.Id;
            option.name = row.Name;
            option.locationName = row.Location_Name__c;
            option.slotDurationMinutes = row.Slot_Duration_Minutes__c == null
                ? null
                : Integer.valueOf(row.Slot_Duration_Minutes__c);
            option.active = row.Active__c;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static ActionResult rescheduleAppointment(Id appointmentId, Id newSlotId) {
        if (appointmentId == null) {
            throw error('An appointment is required.');
        }
        if (newSlotId == null) {
            throw error('A free slot is required to reschedule.');
        }

        Appointment__c appointment = requireAppointment(appointmentId);
        requireOpenStatus(appointment, 'reschedule');
        if (appointment.Slot__c == newSlotId) {
            throw error('Choose a different free slot.');
        }

        Set<Id> slotIds = new Set<Id>{ newSlotId };
        if (appointment.Slot__c != null) {
            slotIds.add(appointment.Slot__c);
        }
        Map<Id, Slot__c> locked = lockSlots(slotIds);
        Slot__c newSlot = locked.get(newSlotId);
        if (newSlot == null) {
            throw error('The new slot was not found.');
        }
        if (newSlot.Status__c != SLOT_FREE) {
            return failure(
                'This slot is no longer available. It is ' +
                    (String.isBlank(newSlot.Status__c) ? 'not Free' : newSlot.Status__c) +
                    '. Choose another time.',
                appointment
            );
        }
        if (newSlot.Schedule__r == null || newSlot.Schedule__r.Practitioner__c == null) {
            throw error('This slot is not assigned to a provider.');
        }

        List<Slot__c> slotUpdates = new List<Slot__c>();
        Slot__c previousSlot = appointment.Slot__c == null ? null : locked.get(appointment.Slot__c);
        Id previousSlotId = appointment.Slot__c;
        if (previousSlot != null) {
            previousSlot.Status__c = SLOT_FREE;
            slotUpdates.add(previousSlot);
        }
        newSlot.Status__c = SLOT_BUSY;
        slotUpdates.add(newSlot);
        update slotUpdates;

        appointment.Slot__c = newSlot.Id;
        appointment.Start__c = newSlot.Start__c;
        appointment.End__c = newSlot.End__c;
        appointment.Practitioner__c = newSlot.Schedule__r.Practitioner__c;
        appointment.Location_Name__c = newSlot.Schedule__r.Location_Name__c;
        update appointment;

        Appointment__c saved = requireAppointment(appointment.Id);
        ActionResult result = toActionResult(saved);
        result.slotId = newSlot.Id;
        result.slotStatus = SLOT_BUSY;
        result.previousSlotId = previousSlotId;
        result.previousSlotStatus = previousSlot == null ? null : SLOT_FREE;
        result.freedSlotId = previousSlotId;
        result.busiedSlotId = newSlot.Id;
        return result;
    }

    @AuraEnabled
    public static ActionResult bookAppointment(
        Id patientId,
        Id slotId,
        String appointmentType,
        String reason
    ) {
        if (patientId == null) {
            throw error('A patient is required.');
        }
        if (slotId == null) {
            throw error('A slot is required.');
        }
        String typeValue = String.isBlank(appointmentType) ? null : appointmentType.trim();
        if (String.isBlank(typeValue) || !APPOINTMENT_TYPES.contains(typeValue)) {
            throw error('Select a valid appointment type.');
        }
        String reasonValue = String.isBlank(reason) ? null : reason.trim();

        if ([SELECT COUNT() FROM Patient__c WHERE Id = :patientId] == 0) {
            throw error('Patient was not found.');
        }

        List<Slot__c> locked = [
            SELECT
                Id,
                Status__c,
                Start__c,
                End__c,
                Schedule__c,
                Schedule__r.Practitioner__c,
                Schedule__r.Location_Name__c
            FROM Slot__c
            WHERE Id = :slotId
            FOR UPDATE
        ];
        if (locked.isEmpty()) {
            throw error('Slot was not found.');
        }

        Slot__c slot = locked[0];
        if (slot.Status__c != SLOT_FREE) {
            return failure(
                'This slot is no longer available. It is ' +
                    (String.isBlank(slot.Status__c) ? 'not Free' : slot.Status__c) +
                    '. Choose another time.',
                null
            );
        }
        if (slot.Schedule__r == null || slot.Schedule__r.Practitioner__c == null) {
            throw error('This slot is not assigned to a provider.');
        }

        slot.Status__c = SLOT_BUSY;
        update slot;

        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Practitioner__c = slot.Schedule__r.Practitioner__c,
            Slot__c = slot.Id,
            Start__c = slot.Start__c,
            End__c = slot.End__c,
            Location_Name__c = slot.Schedule__r.Location_Name__c,
            Appointment_Type__c = typeValue,
            Reason__c = reasonValue,
            Status__c = APPT_BOOKED
        );
        insert appointment;

        Appointment__c saved = requireAppointment(appointment.Id);
        ActionResult result = toActionResult(saved);
        result.slotId = slot.Id;
        result.slotStatus = SLOT_BUSY;
        result.busiedSlotId = slot.Id;
        return result;
    }

    @AuraEnabled
    public static ActionResult cancelAppointment(Id appointmentId) {
        Appointment__c appointment = requireAppointment(appointmentId);
        if (appointment.Status__c == APPT_CANCELLED) {
            throw error('This appointment is already cancelled.');
        }
        if (!OPEN_STATUSES.contains(appointment.Status__c) && appointment.Status__c != APPT_ARRIVED) {
            throw error('Only booked, proposed, or arrived appointments can be cancelled.');
        }

        appointment.Status__c = APPT_CANCELLED;
        update appointment;

        Appointment__c saved = requireAppointment(appointment.Id);
        ActionResult result = toActionResult(saved);
        result.slotId = saved.Slot__c;
        if (saved.Slot__c != null) {
            List<Slot__c> locked = [
                SELECT Id, Status__c
                FROM Slot__c
                WHERE Id = :saved.Slot__c
                FOR UPDATE
            ];
            if (!locked.isEmpty()) {
                locked[0].Status__c = SLOT_FREE;
                update locked;
                result.slotStatus = SLOT_FREE;
                result.freedSlotId = saved.Slot__c;
            }
        }
        return result;
    }

    @AuraEnabled
    public static ActionResult markNoShow(Id appointmentId) {
        Appointment__c appointment = requireAppointment(appointmentId);
        requireOpenStatus(appointment, 'mark no show');
        appointment.Status__c = APPT_NO_SHOW;
        update appointment;

        Appointment__c saved = requireAppointment(appointment.Id);
        ActionResult result = toActionResult(saved);
        result.slotId = saved.Slot__c;
        if (saved.Slot__c != null) {
            List<Slot__c> slots = [SELECT Id, Status__c FROM Slot__c WHERE Id = :saved.Slot__c];
            result.slotStatus = slots.isEmpty() ? null : slots[0].Status__c;
            result.busiedSlotId = saved.Slot__c;
        }
        return result;
    }

    @AuraEnabled
    public static ActionResult arriveAppointment(Id appointmentId) {
        Appointment__c appointment = requireAppointment(appointmentId);
        requireOpenStatus(appointment, 'arrive');
        if (appointment.Encounter__c != null) {
            throw error('This appointment already has an encounter.');
        }
        if (appointment.Patient__c == null) {
            throw error('A patient is required to arrive this appointment.');
        }

        Encounter__c encounter = new Encounter__c(
            Patient__c = appointment.Patient__c,
            Practitioner__c = appointment.Practitioner__c,
            Start__c = Datetime.now(),
            Status__c = ENC_ARRIVED,
            Class__c = classForAppointmentType(appointment.Appointment_Type__c),
            Location_Name__c = appointment.Location_Name__c,
            Reason__c = appointment.Reason__c
        );
        insert encounter;

        appointment.Status__c = APPT_ARRIVED;
        appointment.Encounter__c = encounter.Id;
        update appointment;

        Encounter__c savedEncounter = [
            SELECT Id, Name
            FROM Encounter__c
            WHERE Id = :encounter.Id
            LIMIT 1
        ];
        Appointment__c saved = requireAppointment(appointment.Id);
        ActionResult result = toActionResult(saved);
        result.encounterId = savedEncounter.Id;
        result.encounterName = savedEncounter.Name;
        result.slotId = saved.Slot__c;
        return result;
    }

    @AuraEnabled
    public static AdHocSlotResult createAdHocSlots(Id scheduleId, List<SlotRange> ranges) {
        Schedule__c schedule = lockSchedule(scheduleId);
        List<RangeCandidate> candidates = normalizeRanges(ranges);
        AdHocSlotResult result = new AdHocSlotResult();
        result.success = true;
        result.slots = new List<Slot__c>();
        result.created = 0;
        result.skipped = 0;

        if (candidates.isEmpty()) {
            Integer invalidCount = countSubmittedRanges(ranges);
            result.skipped = invalidCount;
            return result;
        }

        Datetime windowStart = candidates[0].startTime;
        Datetime windowEnd = candidates[0].endTime;
        for (RangeCandidate candidate : candidates) {
            if (candidate.startTime < windowStart) {
                windowStart = candidate.startTime;
            }
            if (candidate.endTime > windowEnd) {
                windowEnd = candidate.endTime;
            }
        }

        List<RangeCandidate> occupied = new List<RangeCandidate>();
        for (Slot__c existing : [
            SELECT Id, Start__c, End__c
            FROM Slot__c
            WHERE Schedule__c = :schedule.Id AND Start__c < :windowEnd AND End__c > :windowStart
        ]) {
            if (existing.Start__c != null && existing.End__c != null) {
                occupied.add(new RangeCandidate(existing.Start__c, existing.End__c));
            }
        }

        List<Slot__c> toInsert = new List<Slot__c>();
        Integer submitted = countSubmittedRanges(ranges);
        for (RangeCandidate candidate : candidates) {
            if (overlapsAny(candidate, occupied)) {
                result.skipped++;
                continue;
            }
            toInsert.add(
                new Slot__c(
                    Schedule__c = schedule.Id,
                    Start__c = candidate.startTime,
                    End__c = candidate.endTime,
                    Status__c = SLOT_FREE
                )
            );
            occupied.add(candidate);
        }
        result.skipped += submitted - candidates.size();

        if (!toInsert.isEmpty()) {
            insert toInsert;
            result.slots = [
                SELECT Id, Start__c, End__c, Status__c, Schedule__c
                FROM Slot__c
                WHERE Id IN :toInsert
                ORDER BY Start__c ASC
            ];
        }
        result.created = toInsert.size();
        return result;
    }

    private static List<Slot__c> querySlots(
        Id practitionerId,
        Boolean filterLocation,
        String locationFilter,
        Datetime windowStart,
        Datetime windowEnd,
        Integer queryLimit
    ) {
        if (practitionerId != null && filterLocation) {
            return [
                SELECT
                    Id,
                    Start__c,
                    End__c,
                    Status__c,
                    Appointment_Type__c,
                    Schedule__c,
                    Schedule__r.Location_Name__c,
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name,
                    Schedule__r.Slot_Duration_Minutes__c,
                    (
                        SELECT
                            Id,
                            Name,
                            Status__c,
                            Appointment_Type__c,
                            Reason__c,
                            Patient__c,
                            Patient__r.Name,
                            Encounter__c,
                            Encounter__r.Name
                        FROM Appointments__r
                        ORDER BY CreatedDate DESC
                        LIMIT 5
                    )
                FROM Slot__c
                WHERE
                    Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Schedule__r.Location_Name__c = :locationFilter
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                ORDER BY Start__c ASC
                LIMIT :queryLimit
            ];
        }
        if (practitionerId != null) {
            return [
                SELECT
                    Id,
                    Start__c,
                    End__c,
                    Status__c,
                    Appointment_Type__c,
                    Schedule__c,
                    Schedule__r.Location_Name__c,
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name,
                    Schedule__r.Slot_Duration_Minutes__c,
                    (
                        SELECT
                            Id,
                            Name,
                            Status__c,
                            Appointment_Type__c,
                            Reason__c,
                            Patient__c,
                            Patient__r.Name,
                            Encounter__c,
                            Encounter__r.Name
                        FROM Appointments__r
                        ORDER BY CreatedDate DESC
                        LIMIT 5
                    )
                FROM Slot__c
                WHERE
                    Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                ORDER BY Start__c ASC
                LIMIT :queryLimit
            ];
        }
        return [
            SELECT
                Id,
                Start__c,
                End__c,
                Status__c,
                Appointment_Type__c,
                Schedule__c,
                Schedule__r.Location_Name__c,
                Schedule__r.Practitioner__c,
                Schedule__r.Practitioner__r.Name,
                Schedule__r.Slot_Duration_Minutes__c,
                (
                    SELECT
                        Id,
                        Name,
                        Status__c,
                        Appointment_Type__c,
                        Reason__c,
                        Patient__c,
                        Patient__r.Name,
                        Encounter__c,
                        Encounter__r.Name
                    FROM Appointments__r
                    ORDER BY CreatedDate DESC
                    LIMIT 5
                )
            FROM Slot__c
            WHERE
                Schedule__r.Active__c = TRUE
                AND Schedule__r.Location_Name__c = :locationFilter
                AND Start__c >= :windowStart
                AND Start__c < :windowEnd
            ORDER BY Start__c ASC
            LIMIT :queryLimit
        ];
    }

    private static Appointment__c requireAppointment(Id appointmentId) {
        if (appointmentId == null) {
            throw error('An appointment is required.');
        }
        List<Appointment__c> rows = [
            SELECT
                Id,
                Name,
                Status__c,
                Appointment_Type__c,
                Reason__c,
                Patient__c,
                Practitioner__c,
                Slot__c,
                Start__c,
                End__c,
                Location_Name__c,
                Encounter__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw error('Appointment was not found.');
        }
        return rows[0];
    }

    private static void requireOpenStatus(Appointment__c appointment, String actionLabel) {
        if (!OPEN_STATUSES.contains(appointment.Status__c)) {
            throw error(
                'Only booked or proposed appointments can be used to ' +
                    actionLabel +
                    '. This appointment is ' +
                    (String.isBlank(appointment.Status__c) ? 'not open' : appointment.Status__c) +
                    '.'
            );
        }
    }

    private static Map<Id, Slot__c> lockSlots(Set<Id> slotIds) {
        Map<Id, Slot__c> locked = new Map<Id, Slot__c>();
        if (slotIds == null || slotIds.isEmpty()) {
            return locked;
        }
        for (Slot__c row : [
            SELECT
                Id,
                Status__c,
                Start__c,
                End__c,
                Schedule__c,
                Schedule__r.Practitioner__c,
                Schedule__r.Location_Name__c
            FROM Slot__c
            WHERE Id IN :slotIds
            FOR UPDATE
        ]) {
            locked.put(row.Id, row);
        }
        return locked;
    }

    private static SlotView toSlotView(Slot__c row) {
        SlotView view = new SlotView();
        view.id = row.Id;
        view.startTime = row.Start__c;
        view.endTime = row.End__c;
        view.status = row.Status__c;
        view.appointmentType = row.Appointment_Type__c;
        view.locationName = row.Schedule__r == null ? null : row.Schedule__r.Location_Name__c;
        view.practitionerId = row.Schedule__r == null ? null : row.Schedule__r.Practitioner__c;
        view.practitionerName = row.Schedule__r == null || row.Schedule__r.Practitioner__r == null
            ? null
            : row.Schedule__r.Practitioner__r.Name;
        view.scheduleId = row.Schedule__c;
        if (row.Start__c != null && row.End__c != null) {
            view.durationMinutes = Integer.valueOf((row.End__c.getTime() - row.Start__c.getTime()) / 60000);
        }
        view.appointment = chooseAppointment(row.Appointments__r);
        return view;
    }

    private static AppointmentView chooseAppointment(List<Appointment__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return null;
        }
        for (Appointment__c row : rows) {
            if (row.Status__c != APPT_CANCELLED) {
                return toAppointmentView(row);
            }
        }
        return null;
    }

    private static AppointmentView toAppointmentView(Appointment__c row) {
        AppointmentView view = new AppointmentView();
        view.id = row.Id;
        view.name = row.Name;
        view.status = row.Status__c;
        view.appointmentType = row.Appointment_Type__c;
        view.reason = row.Reason__c;
        view.patientId = row.Patient__c;
        view.patientName = row.Patient__r == null ? null : row.Patient__r.Name;
        view.encounterId = row.Encounter__c;
        view.encounterName = row.Encounter__r == null ? null : row.Encounter__r.Name;
        return view;
    }

    private static ActionResult toActionResult(Appointment__c appointment) {
        ActionResult result = new ActionResult();
        result.success = true;
        result.appointment = appointment;
        result.appointmentId = appointment.Id;
        result.appointmentName = appointment.Name;
        result.appointmentStatus = appointment.Status__c;
        result.encounterId = appointment.Encounter__c;
        return result;
    }

    private static ActionResult failure(String reason, Appointment__c appointment) {
        ActionResult result = new ActionResult();
        result.success = false;
        result.reason = reason;
        result.appointment = appointment;
        if (appointment != null) {
            result.appointmentId = appointment.Id;
            result.appointmentName = appointment.Name;
            result.appointmentStatus = appointment.Status__c;
            result.encounterId = appointment.Encounter__c;
        }
        return result;
    }

    private static Schedule__c lockSchedule(Id scheduleId) {
        if (scheduleId == null) {
            throw error('A schedule is required.');
        }
        List<Schedule__c> rows = [
            SELECT Id
            FROM Schedule__c
            WHERE Id = :scheduleId
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw error('Schedule was not found.');
        }
        return rows[0];
    }

    private static List<RangeCandidate> normalizeRanges(List<SlotRange> ranges) {
        List<RangeCandidate> candidates = new List<RangeCandidate>();
        if (ranges == null) {
            return candidates;
        }
        Set<String> seen = new Set<String>();
        for (SlotRange range : ranges) {
            if (range == null || range.startTime == null || range.endTime == null) {
                continue;
            }
            if (range.endTime <= range.startTime) {
                continue;
            }
            String key = String.valueOf(range.startTime.getTime()) + ':' + String.valueOf(range.endTime.getTime());
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);
            candidates.add(new RangeCandidate(range.startTime, range.endTime));
        }
        candidates.sort();
        return candidates;
    }

    private static Integer countSubmittedRanges(List<SlotRange> ranges) {
        if (ranges == null) {
            return 0;
        }
        Integer count = 0;
        for (SlotRange range : ranges) {
            if (range != null) {
                count++;
            }
        }
        return count;
    }

    private static Boolean overlapsAny(RangeCandidate candidate, List<RangeCandidate> occupied) {
        for (RangeCandidate existing : occupied) {
            if (overlaps(candidate, existing)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean overlaps(RangeCandidate left, RangeCandidate right) {
        return left.startTime < right.endTime && right.startTime < left.endTime;
    }

    private class RangeCandidate implements Comparable {
        public Datetime startTime;
        public Datetime endTime;

        public RangeCandidate(Datetime startTime, Datetime endTime) {
            this.startTime = startTime;
            this.endTime = endTime;
        }

        public Integer compareTo(Object other) {
            RangeCandidate that = (RangeCandidate) other;
            Long thisStart = this.startTime.getTime();
            Long thatStart = that.startTime.getTime();
            if (thisStart == thatStart) {
                Long thisEnd = this.endTime.getTime();
                Long thatEnd = that.endTime.getTime();
                if (thisEnd == thatEnd) {
                    return 0;
                }
                return thisEnd > thatEnd ? 1 : -1;
            }
            return thisStart > thatStart ? 1 : -1;
        }
    }

    private static String classForAppointmentType(String appointmentType) {
        if (appointmentType == ENC_CLASS_EMERGENCY) {
            return ENC_CLASS_EMERGENCY;
        }
        return ENC_CLASS_DEFAULT;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
