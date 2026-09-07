/**
 * Idempotent seed for Schedule, Slot, and Appointment.
 * Requires seedDemoData.apex. Re-run safe via Source_System_Id__c upsert.
 * Do not set Appointment Name — composed by NameFormatterHandler.
 *
 * Times are relative to Date.today() so the Scheduling calendar,
 * Today's Appointments, Upcoming, and provider home stay populated.
 */
new SeedRunner().run();

class SeedRunner {
    void run() {
        Map<String, Id> ptIds = loadIds(
            [
                SELECT Id, lfemr__Source_System_Id__c
                FROM lfemr__Patient__c
                WHERE lfemr__Source_System_Id__c LIKE 'seed-pt-%'
            ]
        );
        Map<String, Id> pracIds = loadIds(
            [
                SELECT Id, lfemr__Source_System_Id__c
                FROM lfemr__Practitioner__c
                WHERE lfemr__Source_System_Id__c LIKE 'seed-prac-%'
            ]
        );
        Map<String, Id> encIds = loadIds(
            [
                SELECT Id, lfemr__Source_System_Id__c
                FROM lfemr__Encounter__c
                WHERE lfemr__Source_System_Id__c LIKE 'seed-enc-%'
            ]
        );
        if (ptIds.size() < 10 || pracIds.size() < 4) {
            throw new AuraHandledException('Run scripts/apex/seedDemoData.apex first.');
        }

        Id maya = ptIds.get('seed-pt-maya-chen');
        Id liam = ptIds.get('seed-pt-liam-chen');
        Id sofia = ptIds.get('seed-pt-sofia-rivera');
        Id noah = ptIds.get('seed-pt-noah-rivera');
        Id james = ptIds.get('seed-pt-james-okonkwo');
        Id ava = ptIds.get('seed-pt-ava-thompson');
        Id ethan = ptIds.get('seed-pt-ethan-brooks');
        Id olivia = ptIds.get('seed-pt-olivia-kim');
        Id benjamin = ptIds.get('seed-pt-benjamin-alvarez');
        Id harper = ptIds.get('seed-pt-harper-nguyen');
        Id lee = pracIds.get('seed-prac-lee');
        Id patel = pracIds.get('seed-prac-patel');
        Id chen = pracIds.get('seed-prac-chen');
        Id vasquez = pracIds.get('seed-prac-vasquez');

        Date today = Date.today();
        Date horizonStart = today.addDays(-7);
        Date horizonEnd = today.addDays(21);

        List<lfemr__Schedule__c> schedules = new List<lfemr__Schedule__c>{
            newSchedule('seed-sch-lee-clinic-a', lee, 'Primary Care Clinic A', 20, horizonStart, horizonEnd, true),
            newSchedule('seed-sch-lee-clinic-b', lee, 'Primary Care Clinic B', 20, horizonStart, today.addDays(-1), false),
            newSchedule('seed-sch-patel-cardio', patel, 'Cardiology Clinic', 30, horizonStart, horizonEnd, true),
            newSchedule('seed-sch-patel-tele', patel, 'Telehealth', 20, horizonStart, horizonEnd, true),
            newSchedule('seed-sch-vasquez-peds', vasquez, 'Pediatrics', 20, horizonStart, horizonEnd, true),
            newSchedule('seed-sch-chen-ed', chen, 'Emergency Department', 20, horizonStart, horizonEnd, true)
        };
        upsert schedules lfemr__Source_System_Id__c;

        Map<String, Id> schIds = new Map<String, Id>();
        for (lfemr__Schedule__c row : schedules) {
            schIds.put(row.lfemr__Source_System_Id__c, row.Id);
        }

        Map<String, lfemr__Slot__c> slotsByKey = new Map<String, lfemr__Slot__c>();
        Date sunday = Date.newInstance(1900, 1, 7);
        for (Integer offset = -7; offset <= 14; offset++) {
            Date day = today.addDays(offset);
            Integer dow = Math.mod(sunday.daysBetween(day), 7);
            Boolean weekday = dow >= 1 && dow <= 5;
            Boolean nearToday = offset >= -1 && offset <= 1;
            if (weekday || nearToday) {
                addGrid(slotsByKey, schIds.get('seed-sch-lee-clinic-a'), 'lee-a', offset, day, 8, 17, 20, 12, 13);
                addGrid(slotsByKey, schIds.get('seed-sch-patel-cardio'), 'patel-c', offset, day, 9, 16, 30, 12, 13);
                addGrid(slotsByKey, schIds.get('seed-sch-vasquez-peds'), 'vasq-p', offset, day, 9, 16, 20, 12, 13);
            }
            if (weekday || nearToday || dow == 6) {
                addGrid(slotsByKey, schIds.get('seed-sch-chen-ed'), 'chen-e', offset, day, 12, 20, 20, null, null);
            }
            if (dow == 2 || dow == 4 || offset == 7) {
                addGrid(slotsByKey, schIds.get('seed-sch-patel-tele'), 'patel-t', offset, day, 16, 18, 20, null, null);
            }
        }

        List<ApptSpec> specs = new List<ApptSpec>{
            new ApptSpec('seed-appt-maya-lee-arrived', 'lee-a', 0, 9, 0, 20, maya, lee, 'Primary Care Clinic A', 'Follow-up', 'Arrived', 'Follow-up hypertension', encIds.get('seed-enc-maya-progress')),
            new ApptSpec('seed-appt-liam-lee-booked', 'lee-a', 0, 10, 0, 20, liam, lee, 'Primary Care Clinic A', 'Checkup', 'Booked', '6-year well child follow-up', null),
            new ApptSpec('seed-appt-ben-lee-booked', 'lee-a', 0, 11, 0, 20, benjamin, lee, 'Primary Care Clinic A', 'Routine', 'Booked', 'Lipid panel review', encIds.get('seed-enc-ben-finished')),
            new ApptSpec('seed-appt-harper-lee-proposed', 'lee-a', 0, 14, 0, 20, harper, lee, 'Primary Care Clinic A', 'Walk-in', 'Proposed', 'Sports physical paperwork', null),
            new ApptSpec('seed-appt-james-lee-fulfilled', 'lee-a', -1, 15, 0, 20, james, lee, 'Primary Care Clinic A', 'Follow-up', 'Fulfilled', 'Hip fracture follow-up', encIds.get('seed-enc-james-ip')),
            new ApptSpec('seed-appt-olivia-lee-booked', 'lee-a', 1, 9, 0, 20, olivia, lee, 'Primary Care Clinic A', 'Checkup', 'Booked', 'Annual physical', encIds.get('seed-enc-olivia-planned')),
            new ApptSpec('seed-appt-ava-lee-cancelled', 'lee-a', -3, 10, 0, 20, ava, lee, 'Primary Care Clinic A', 'Checkup', 'Cancelled', 'Annual physical — patient inactive', null),
            new ApptSpec('seed-appt-maya-lee-cancelled', 'lee-a', -2, 8, 0, 20, maya, lee, 'Primary Care Clinic A', 'Checkup', 'Cancelled', 'Annual physical', encIds.get('seed-enc-maya-cancelled')),
            new ApptSpec('seed-appt-sofia-patel-arrived', 'patel-c', 0, 13, 30, 30, sofia, patel, 'Cardiology Clinic', 'Follow-up', 'Arrived', 'Palpitations', encIds.get('seed-enc-sofia-progress')),
            new ApptSpec('seed-appt-ben-patel-booked', 'patel-c', 2, 9, 0, 30, benjamin, patel, 'Cardiology Clinic', 'Follow-up', 'Booked', 'Stress test follow-up', encIds.get('seed-enc-ben-progress')),
            new ApptSpec('seed-appt-sofia-patel-booked', 'patel-c', 5, 10, 0, 30, sofia, patel, 'Cardiology Clinic', 'Follow-up', 'Booked', 'Cardiology follow-up', null),
            new ApptSpec('seed-appt-maya-patel-tele', 'patel-t', 7, 16, 0, 20, maya, patel, 'Telehealth', 'Follow-up', 'Booked', 'Endocrine consult', encIds.get('seed-enc-maya-planned')),
            new ApptSpec('seed-appt-ethan-vasq-arrived', 'vasq-p', 0, 15, 20, 20, ethan, vasquez, 'Pediatrics', 'Checkup', 'Arrived', '12-month well child', encIds.get('seed-enc-ethan-well')),
            new ApptSpec('seed-appt-noah-vasq-booked', 'vasq-p', 4, 10, 0, 20, noah, vasquez, 'Pediatrics', 'Checkup', 'Booked', '4-month well child', encIds.get('seed-enc-noah-well')),
            new ApptSpec('seed-appt-liam-vasq-noshow', 'vasq-p', -4, 14, 40, 20, liam, vasquez, 'Pediatrics', 'Follow-up', 'No Show', 'Otitis media follow-up', encIds.get('seed-enc-liam-sick')),
            new ApptSpec('seed-appt-james-chen-ed', 'chen-e', -6, 19, 0, 20, james, chen, 'Emergency Department', 'Emergency', 'Fulfilled', 'Fall, hip pain', encIds.get('seed-enc-james-ed')),
            new ApptSpec('seed-appt-olivia-chen-proposed', 'chen-e', 3, 17, 0, 20, olivia, chen, 'Emergency Department', 'Emergency', 'Proposed', 'Chest pain rule-out', null),
            new ApptSpec('seed-appt-harper-chen-walkin', 'chen-e', 0, 18, 0, 20, harper, chen, 'Emergency Department', 'Walk-in', 'Booked', 'Ankle sprain after practice', null)
        };

        Map<String, String> schSourceByKey = new Map<String, String>{
            'lee-a' => 'seed-sch-lee-clinic-a',
            'patel-c' => 'seed-sch-patel-cardio',
            'patel-t' => 'seed-sch-patel-tele',
            'vasq-p' => 'seed-sch-vasquez-peds',
            'chen-e' => 'seed-sch-chen-ed'
        };
        Set<String> busyStatuses = new Set<String>{ 'Proposed', 'Booked', 'Arrived', 'Fulfilled' };
        Set<String> busyKeys = new Set<String>();
        for (ApptSpec spec : specs) {
            String key = slotKey(spec.schKey, spec.dayOffset, spec.hour, spec.minute);
            Date day = today.addDays(spec.dayOffset);
            Datetime startAt = Datetime.newInstance(day, Time.newInstance(spec.hour, spec.minute, 0, 0));
            if (!slotsByKey.containsKey(key)) {
                slotsByKey.put(
                    key,
                    newSlot(schIds.get(schSourceByKey.get(spec.schKey)), key, startAt, startAt.addMinutes(spec.minutes), 'Free', spec.apptType)
                );
            }
            if (busyStatuses.contains(spec.status)) {
                busyKeys.add(key);
            }
        }

        List<lfemr__Slot__c> slots = slotsByKey.values();
        Integer batchSize = 200;
        for (Integer i = 0; i < slots.size(); i += batchSize) {
            List<lfemr__Slot__c> chunk = new List<lfemr__Slot__c>();
            Integer last = Math.min(i + batchSize, slots.size());
            for (Integer j = i; j < last; j++) {
                chunk.add(slots[j]);
            }
            upsert chunk lfemr__Source_System_Id__c;
        }

        List<lfemr__Appointment__c> appointments = new List<lfemr__Appointment__c>();
        for (ApptSpec spec : specs) {
            String key = slotKey(spec.schKey, spec.dayOffset, spec.hour, spec.minute);
            lfemr__Slot__c slot = slotsByKey.get(key);
            Date day = today.addDays(spec.dayOffset);
            Datetime startAt = Datetime.newInstance(day, Time.newInstance(spec.hour, spec.minute, 0, 0));
            appointments.add(
                new lfemr__Appointment__c(
                    lfemr__Source_System_Id__c = spec.sourceId,
                    lfemr__FHIR_Id__c = spec.sourceId,
                    lfemr__Patient__c = spec.patientId,
                    lfemr__Practitioner__c = spec.practitionerId,
                    lfemr__Slot__c = slot == null ? null : slot.Id,
                    lfemr__Encounter__c = spec.encounterId,
                    lfemr__Start__c = startAt,
                    lfemr__End__c = startAt.addMinutes(spec.minutes),
                    lfemr__Location_Name__c = spec.locationName,
                    lfemr__Appointment_Type__c = spec.apptType,
                    lfemr__Status__c = spec.status,
                    lfemr__Reason__c = spec.reason
                )
            );
        }
        upsert appointments lfemr__Source_System_Id__c;

        List<lfemr__Slot__c> busyUpdates = new List<lfemr__Slot__c>();
        for (String key : busyKeys) {
            lfemr__Slot__c slot = slotsByKey.get(key);
            if (slot != null && slot.lfemr__Status__c != 'Blocked') {
                slot.lfemr__Status__c = 'Busy';
                busyUpdates.add(slot);
            }
        }
        if (!busyUpdates.isEmpty()) {
            update busyUpdates;
        }

        System.debug(
            'Seeded ' +
                schedules.size() +
                ' schedules, ' +
                slots.size() +
                ' slots, ' +
                appointments.size() +
                ' appointments.'
        );
    }

    Map<String, Id> loadIds(List<SObject> rows) {
        Map<String, Id> ids = new Map<String, Id>();
        for (SObject row : rows) {
            ids.put((String) row.get('lfemr__Source_System_Id__c'), row.Id);
        }
        return ids;
    }

    lfemr__Schedule__c newSchedule(
        String sourceId,
        Id practitionerId,
        String locationName,
        Integer duration,
        Date horizonStart,
        Date horizonEnd,
        Boolean active
    ) {
        return new lfemr__Schedule__c(
            lfemr__Source_System_Id__c = sourceId,
            lfemr__FHIR_Id__c = sourceId,
            lfemr__Practitioner__c = practitionerId,
            lfemr__Location_Name__c = locationName,
            lfemr__Slot_Duration_Minutes__c = duration,
            lfemr__Planning_Horizon_Start__c = horizonStart,
            lfemr__Planning_Horizon_End__c = horizonEnd,
            lfemr__Active__c = active
        );
    }

    void addGrid(
        Map<String, lfemr__Slot__c> slotsByKey,
        Id scheduleId,
        String schKey,
        Integer offset,
        Date day,
        Integer startHour,
        Integer endHour,
        Integer duration,
        Integer blockStartHour,
        Integer blockEndHour
    ) {
        Datetime cursor = Datetime.newInstance(day, Time.newInstance(startHour, 0, 0, 0));
        Datetime windowEnd = Datetime.newInstance(day, Time.newInstance(endHour, 0, 0, 0));
        while (cursor < windowEnd) {
            Datetime slotEnd = cursor.addMinutes(duration);
            if (slotEnd > windowEnd) {
                break;
            }
            Integer hour = cursor.hour();
            Integer minute = cursor.minute();
            String key = slotKey(schKey, offset, hour, minute);
            String status = 'Free';
            if (blockStartHour != null && hour >= blockStartHour && hour < blockEndHour) {
                status = 'Blocked';
            }
            slotsByKey.put(key, newSlot(scheduleId, key, cursor, slotEnd, status, null));
            cursor = slotEnd;
        }
    }

    lfemr__Slot__c newSlot(Id scheduleId, String key, Datetime startAt, Datetime endAt, String status, String apptType) {
        return new lfemr__Slot__c(
            lfemr__Source_System_Id__c = key,
            lfemr__FHIR_Id__c = key,
            lfemr__Schedule__c = scheduleId,
            lfemr__Start__c = startAt,
            lfemr__End__c = endAt,
            lfemr__Status__c = status,
            lfemr__Appointment_Type__c = apptType
        );
    }

    String slotKey(String schKey, Integer offset, Integer hour, Integer minute) {
        String hh = hour < 10 ? '0' + String.valueOf(hour) : String.valueOf(hour);
        String mm = minute < 10 ? '0' + String.valueOf(minute) : String.valueOf(minute);
        return 'seed-sl-' + schKey + '-d' + String.valueOf(offset) + '-' + hh + mm;
    }
}

class ApptSpec {
    String sourceId;
    String schKey;
    Integer dayOffset;
    Integer hour;
    Integer minute;
    Integer minutes;
    Id patientId;
    Id practitionerId;
    String locationName;
    String apptType;
    String status;
    String reason;
    Id encounterId;
    ApptSpec(
        String sourceId,
        String schKey,
        Integer dayOffset,
        Integer hour,
        Integer minute,
        Integer minutes,
        Id patientId,
        Id practitionerId,
        String locationName,
        String apptType,
        String status,
        String reason,
        Id encounterId
    ) {
        this.sourceId = sourceId;
        this.schKey = schKey;
        this.dayOffset = dayOffset;
        this.hour = hour;
        this.minute = minute;
        this.minutes = minutes;
        this.patientId = patientId;
        this.practitionerId = practitionerId;
        this.locationName = locationName;
        this.apptType = apptType;
        this.status = status;
        this.reason = reason;
        this.encounterId = encounterId;
    }
}
