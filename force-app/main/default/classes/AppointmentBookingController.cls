public with sharing class AppointmentBookingController {
    private static final String SLOT_FREE = 'Free';
    private static final String SLOT_BUSY = 'Busy';
    private static final String APPT_BOOKED = 'Booked';
    private static final Integer SLOT_QUERY_LIMIT = 200;
    @TestVisible
    private static final Set<String> APPOINTMENT_TYPES = new Set<String>{
        'Checkup',
        'Emergency',
        'Follow-up',
        'Routine',
        'Walk-in'
    };

    public class SlotView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Datetime startTime;
        @AuraEnabled
        public Datetime endTime;
        @AuraEnabled
        public String locationName;
        @AuraEnabled
        public String practitionerName;
        @AuraEnabled
        public Id practitionerId;
    }

    public class SlotListView {
        @AuraEnabled
        public List<SlotView> slots;
        @AuraEnabled
        public Boolean hasMore;
    }

    public class BookingResult {
        @AuraEnabled
        public Id appointmentId;
        @AuraEnabled
        public String appointmentName;
        @AuraEnabled
        public Id slotId;
        @AuraEnabled
        public Datetime startTime;
        @AuraEnabled
        public Datetime endTime;
        @AuraEnabled
        public String status;
    }

    public class ProviderAvailabilityView {
        @AuraEnabled
        public Id practitionerId;
        @AuraEnabled
        public String practitionerName;
        @AuraEnabled
        public String specialty;
        @AuraEnabled
        public String locationNames;
        @AuraEnabled
        public Integer freeSlotCount;
        @AuraEnabled
        public Datetime earliestStart;
        @AuraEnabled
        public Datetime latestStart;
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
    public static List<ProviderAvailabilityView> getAvailableProviders(
        Date rangeStart,
        Date rangeEnd,
        String locationName,
        Boolean includeUnavailable
    ) {
        DateWindow window = toDateWindow(rangeStart, rangeEnd);
        Datetime windowStart = window.startTime;
        Datetime windowEnd = window.endTime;
        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;

        List<AggregateResult> rows;
        if (filterLocation) {
            rows = [
                SELECT
                    Schedule__r.Practitioner__c practitionerId,
                    Schedule__r.Practitioner__r.Name practitionerName,
                    Schedule__r.Practitioner__r.Specialty__c specialty,
                    Schedule__r.Location_Name__c locationName,
                    COUNT(Id) freeSlotCount,
                    MIN(Start__c) earliestStart,
                    MAX(Start__c) latestStart
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c != NULL
                    AND Schedule__r.Practitioner__r.Active__c = TRUE
                    AND Schedule__r.Location_Name__c = :locationFilter
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                GROUP BY
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name,
                    Schedule__r.Practitioner__r.Specialty__c,
                    Schedule__r.Location_Name__c
                ORDER BY Schedule__r.Practitioner__r.Name
            ];
        } else {
            rows = [
                SELECT
                    Schedule__r.Practitioner__c practitionerId,
                    Schedule__r.Practitioner__r.Name practitionerName,
                    Schedule__r.Practitioner__r.Specialty__c specialty,
                    Schedule__r.Location_Name__c locationName,
                    COUNT(Id) freeSlotCount,
                    MIN(Start__c) earliestStart,
                    MAX(Start__c) latestStart
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c != NULL
                    AND Schedule__r.Practitioner__r.Active__c = TRUE
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                GROUP BY
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name,
                    Schedule__r.Practitioner__r.Specialty__c,
                    Schedule__r.Location_Name__c
                ORDER BY Schedule__r.Practitioner__r.Name
            ];
        }
        List<ProviderAvailabilityView> available = mergeProviderAvailability(rows);
        if (includeUnavailable != true) {
            return available;
        }
        return includeProvidersWithoutSlots(available, locationFilter);
    }

    @AuraEnabled
    public static ProviderAvailabilityView getProviderAvailability(
        Id practitionerId,
        Date rangeStart,
        Date rangeEnd,
        String locationName
    ) {
        if (practitionerId == null) {
            throw error('A provider is required.');
        }
        DateWindow window = toDateWindow(rangeStart, rangeEnd);
        List<Practitioner__c> practitioners = [
            SELECT Id, Name, Specialty__c, Active__c
            FROM Practitioner__c
            WHERE Id = :practitionerId
            LIMIT 1
        ];
        if (practitioners.isEmpty()) {
            throw error('Provider was not found.');
        }
        if (practitioners[0].Active__c != true) {
            throw error('This provider is not active.');
        }

        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;
        Datetime windowStart = window.startTime;
        Datetime windowEnd = window.endTime;

        List<AggregateResult> slotRows;
        if (filterLocation) {
            slotRows = [
                SELECT COUNT(Id) freeSlotCount, MIN(Start__c) earliestStart, MAX(Start__c) latestStart
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Schedule__r.Location_Name__c = :locationFilter
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
            ];
        } else {
            slotRows = [
                SELECT COUNT(Id) freeSlotCount, MIN(Start__c) earliestStart, MAX(Start__c) latestStart
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Active__c = TRUE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
            ];
        }

        ProviderAvailabilityView view = new ProviderAvailabilityView();
        view.practitionerId = practitioners[0].Id;
        view.practitionerName = practitioners[0].Name;
        view.specialty = practitioners[0].Specialty__c;
        view.freeSlotCount = 0;
        if (!slotRows.isEmpty()) {
            view.freeSlotCount = slotRows[0].get('freeSlotCount') == null
                ? 0
                : ((Decimal) slotRows[0].get('freeSlotCount')).intValue();
            view.earliestStart = (Datetime) slotRows[0].get('earliestStart');
            view.latestStart = (Datetime) slotRows[0].get('latestStart');
        }
        view.locationNames = scheduleLocationNames(practitionerId, locationFilter);
        return view;
    }

    @AuraEnabled
    public static SlotListView getFreeSlots(
        Id practitionerId,
        String locationName,
        Date rangeStart,
        Date rangeEnd
    ) {
        if (practitionerId == null) {
            throw error('A provider is required.');
        }
        DateWindow window = toDateWindow(rangeStart, rangeEnd);
        Datetime windowStart = window.startTime;
        Datetime windowEnd = window.endTime;
        Integer queryLimit = SLOT_QUERY_LIMIT + 1;
        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;

        List<Slot__c> rows;
        if (filterLocation) {
            rows = [
                SELECT
                    Id,
                    Start__c,
                    End__c,
                    Schedule__r.Location_Name__c,
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Schedule__r.Active__c = TRUE
                    AND Schedule__r.Location_Name__c = :locationFilter
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                ORDER BY Start__c ASC
                LIMIT :queryLimit
            ];
        } else {
            rows = [
                SELECT
                    Id,
                    Start__c,
                    End__c,
                    Schedule__r.Location_Name__c,
                    Schedule__r.Practitioner__c,
                    Schedule__r.Practitioner__r.Name
                FROM Slot__c
                WHERE
                    Status__c = :SLOT_FREE
                    AND Schedule__r.Practitioner__c = :practitionerId
                    AND Schedule__r.Active__c = TRUE
                    AND Start__c >= :windowStart
                    AND Start__c < :windowEnd
                ORDER BY Start__c ASC
                LIMIT :queryLimit
            ];
        }

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
    public static BookingResult bookAppointment(
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

        // Lock the slot row so a concurrent book cannot also see Status = Free.
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
            throw error(
                'This slot is no longer available. It is ' +
                    (String.isBlank(slot.Status__c) ? 'not Free' : slot.Status__c) +
                    '. Choose another time.'
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

        Appointment__c saved = [
            SELECT Id, Name, Status__c, Start__c, End__c, Slot__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
            LIMIT 1
        ];
        return toBookingResult(saved);
    }

    private class DateWindow {
        public Datetime startTime;
        public Datetime endTime;
    }

    private static DateWindow toDateWindow(Date rangeStart, Date rangeEnd) {
        if (rangeStart == null || rangeEnd == null) {
            throw error('A start date and end date are required.');
        }
        if (rangeEnd < rangeStart) {
            throw error('End date must be on or after the start date.');
        }
        DateWindow window = new DateWindow();
        window.startTime = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        window.endTime = DateTime.newInstance(rangeEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        return window;
    }

    private static List<ProviderAvailabilityView> mergeProviderAvailability(List<AggregateResult> rows) {
        Map<Id, ProviderAvailabilityView> byPractitioner = new Map<Id, ProviderAvailabilityView>();
        Map<Id, Set<String>> locationsByPractitioner = new Map<Id, Set<String>>();
        List<Id> order = new List<Id>();

        for (AggregateResult row : rows) {
            Id practitionerId = (Id) row.get('practitionerId');
            if (practitionerId == null) {
                continue;
            }
            Integer slotCount = row.get('freeSlotCount') == null ? 0 : ((Decimal) row.get('freeSlotCount')).intValue();
            Datetime earliest = (Datetime) row.get('earliestStart');
            Datetime latest = (Datetime) row.get('latestStart');
            String locationName = (String) row.get('locationName');

            ProviderAvailabilityView view = byPractitioner.get(practitionerId);
            if (view == null) {
                view = new ProviderAvailabilityView();
                view.practitionerId = practitionerId;
                view.practitionerName = (String) row.get('practitionerName');
                view.specialty = (String) row.get('specialty');
                view.freeSlotCount = slotCount;
                view.earliestStart = earliest;
                view.latestStart = latest;
                byPractitioner.put(practitionerId, view);
                locationsByPractitioner.put(practitionerId, new Set<String>());
                order.add(practitionerId);
            } else {
                view.freeSlotCount += slotCount;
                if (earliest != null && (view.earliestStart == null || earliest < view.earliestStart)) {
                    view.earliestStart = earliest;
                }
                if (latest != null && (view.latestStart == null || latest > view.latestStart)) {
                    view.latestStart = latest;
                }
            }
            if (String.isNotBlank(locationName)) {
                locationsByPractitioner.get(practitionerId).add(locationName);
            }
        }

        List<ProviderAvailabilityView> result = new List<ProviderAvailabilityView>();
        for (Id practitionerId : order) {
            ProviderAvailabilityView view = byPractitioner.get(practitionerId);
            List<String> locationNames = new List<String>(locationsByPractitioner.get(practitionerId));
            locationNames.sort();
            view.locationNames = String.join(locationNames, ', ');
            result.add(view);
        }
        return result;
    }

    private static List<ProviderAvailabilityView> includeProvidersWithoutSlots(
        List<ProviderAvailabilityView> available,
        String locationName
    ) {
        Boolean filterLocation = String.isNotBlank(locationName);
        String locationFilter = filterLocation ? locationName.trim() : null;
        List<Practitioner__c> practitioners = queryActivePractitioners(locationFilter);
        Map<Id, ProviderAvailabilityView> byId = new Map<Id, ProviderAvailabilityView>();
        for (ProviderAvailabilityView view : available) {
            byId.put(view.practitionerId, view);
        }

        Set<Id> practitionerIds = new Set<Id>();
        for (Practitioner__c row : practitioners) {
            practitionerIds.add(row.Id);
        }
        Map<Id, Set<String>> locationsByPractitioner = scheduleLocationsByPractitioner(practitionerIds, locationFilter);

        List<ProviderAvailabilityView> withSlots = new List<ProviderAvailabilityView>();
        List<ProviderAvailabilityView> withoutSlots = new List<ProviderAvailabilityView>();
        for (Practitioner__c row : practitioners) {
            ProviderAvailabilityView view = byId.get(row.Id);
            if (view == null) {
                view = new ProviderAvailabilityView();
                view.practitionerId = row.Id;
                view.practitionerName = row.Name;
                view.specialty = row.Specialty__c;
                view.freeSlotCount = 0;
            }
            if (String.isBlank(view.locationNames) && locationsByPractitioner.containsKey(row.Id)) {
                List<String> locationNames = new List<String>(locationsByPractitioner.get(row.Id));
                locationNames.sort();
                view.locationNames = String.join(locationNames, ', ');
            }
            if (view.freeSlotCount != null && view.freeSlotCount > 0) {
                withSlots.add(view);
            } else {
                withoutSlots.add(view);
            }
        }
        withSlots.addAll(withoutSlots);
        return withSlots;
    }

    private static List<Practitioner__c> queryActivePractitioners(String locationFilter) {
        if (String.isNotBlank(locationFilter)) {
            Set<Id> practitionerIds = new Set<Id>();
            for (Schedule__c schedule : [
                SELECT Practitioner__c
                FROM Schedule__c
                WHERE
                    Active__c = TRUE
                    AND Practitioner__c != NULL
                    AND Practitioner__r.Active__c = TRUE
                    AND Location_Name__c = :locationFilter
            ]) {
                practitionerIds.add(schedule.Practitioner__c);
            }
            if (practitionerIds.isEmpty()) {
                return new List<Practitioner__c>();
            }
            return [
                SELECT Id, Name, Specialty__c
                FROM Practitioner__c
                WHERE Id IN :practitionerIds
                ORDER BY Name
            ];
        }
        return [
            SELECT Id, Name, Specialty__c
            FROM Practitioner__c
            WHERE Active__c = TRUE
            ORDER BY Name
            LIMIT 2000
        ];
    }

    private static Map<Id, Set<String>> scheduleLocationsByPractitioner(
        Set<Id> practitionerIds,
        String locationFilter
    ) {
        Map<Id, Set<String>> locationsByPractitioner = new Map<Id, Set<String>>();
        if (practitionerIds == null || practitionerIds.isEmpty()) {
            return locationsByPractitioner;
        }
        List<Schedule__c> schedules;
        if (String.isNotBlank(locationFilter)) {
            schedules = [
                SELECT Practitioner__c, Location_Name__c
                FROM Schedule__c
                WHERE
                    Active__c = TRUE
                    AND Practitioner__c IN :practitionerIds
                    AND Location_Name__c = :locationFilter
            ];
        } else {
            schedules = [
                SELECT Practitioner__c, Location_Name__c
                FROM Schedule__c
                WHERE Active__c = TRUE AND Practitioner__c IN :practitionerIds AND Location_Name__c != NULL
            ];
        }
        for (Schedule__c schedule : schedules) {
            if (!locationsByPractitioner.containsKey(schedule.Practitioner__c)) {
                locationsByPractitioner.put(schedule.Practitioner__c, new Set<String>());
            }
            if (String.isNotBlank(schedule.Location_Name__c)) {
                locationsByPractitioner.get(schedule.Practitioner__c).add(schedule.Location_Name__c);
            }
        }
        return locationsByPractitioner;
    }

    private static String scheduleLocationNames(Id practitionerId, String locationFilter) {
        List<AggregateResult> locationRows;
        if (String.isNotBlank(locationFilter)) {
            locationRows = [
                SELECT Location_Name__c locationName
                FROM Schedule__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND Location_Name__c = :locationFilter
                GROUP BY Location_Name__c
                ORDER BY Location_Name__c
            ];
        } else {
            locationRows = [
                SELECT Location_Name__c locationName
                FROM Schedule__c
                WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND Location_Name__c != NULL
                GROUP BY Location_Name__c
                ORDER BY Location_Name__c
            ];
        }
        List<String> locationNames = new List<String>();
        for (AggregateResult row : locationRows) {
            String locationName = (String) row.get('locationName');
            if (String.isNotBlank(locationName)) {
                locationNames.add(locationName);
            }
        }
        return String.join(locationNames, ', ');
    }

    private static SlotView toSlotView(Slot__c row) {
        SlotView view = new SlotView();
        view.id = row.Id;
        view.startTime = row.Start__c;
        view.endTime = row.End__c;
        view.locationName = row.Schedule__r == null ? null : row.Schedule__r.Location_Name__c;
        view.practitionerId = row.Schedule__r == null ? null : row.Schedule__r.Practitioner__c;
        view.practitionerName = row.Schedule__r == null || row.Schedule__r.Practitioner__r == null
            ? null
            : row.Schedule__r.Practitioner__r.Name;
        return view;
    }

    private static BookingResult toBookingResult(Appointment__c appointment) {
        BookingResult result = new BookingResult();
        result.appointmentId = appointment.Id;
        result.appointmentName = appointment.Name;
        result.slotId = appointment.Slot__c;
        result.startTime = appointment.Start__c;
        result.endTime = appointment.End__c;
        result.status = appointment.Status__c;
        return result;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
