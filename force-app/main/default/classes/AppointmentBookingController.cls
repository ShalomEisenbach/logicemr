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

    @AuraEnabled
    public static List<String> getLocations(Id practitionerId) {
        if (practitionerId == null) {
            throw error('A provider is required.');
        }

        List<String> locations = new List<String>();
        for (AggregateResult row : [
            SELECT Location_Name__c locationName
            FROM Schedule__c
            WHERE Practitioner__c = :practitionerId AND Active__c = TRUE AND Location_Name__c != NULL
            GROUP BY Location_Name__c
            ORDER BY Location_Name__c
        ]) {
            String locationName = (String) row.get('locationName');
            if (String.isNotBlank(locationName)) {
                locations.add(locationName);
            }
        }
        return locations;
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
