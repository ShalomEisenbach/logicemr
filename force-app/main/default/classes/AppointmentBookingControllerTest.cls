@IsTest
private class AppointmentBookingControllerTest {
    private static final Date SLOT_DAY = Date.newInstance(2026, 9, 8);
    private static final String TYPE_CHECKUP = 'Checkup';

    @IsTest
    static void bookSucceedsAndSecondBookingIsRejected() {
        Patient__c firstPatient = insertPatient('MRN-BOOK-1');
        Patient__c secondPatient = insertPatient('MRN-BOOK-2');
        Practitioner__c practitioner = insertPractitioner('Ada', 'Lopez');
        Schedule__c schedule = insertSchedule(practitioner.Id, 'Clinic A');
        Datetime startTime = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Datetime endTime = startTime.addMinutes(20);
        Slot__c slot = insertSlot(schedule.Id, startTime, endTime, 'Free');

        Test.startTest();
        AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
            firstPatient.Id,
            slot.Id,
            TYPE_CHECKUP,
            'Annual visit'
        );
        Boolean secondRejected = false;
        String rejectMessage;
        try {
            AppointmentBookingController.bookAppointment(
                secondPatient.Id,
                slot.Id,
                'Follow-up',
                'Same slot'
            );
        } catch (AuraHandledException e) {
            secondRejected = true;
            rejectMessage = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, booked.appointmentId, 'First booking should insert an Appointment__c');
        System.assertEquals(slot.Id, booked.slotId, 'Appointment should reference the chosen slot');
        System.assertEquals('Booked', booked.status, 'Appointment status should be Booked');
        System.assertEquals(startTime, booked.startTime, 'Appointment start should come from the slot');
        System.assertEquals(endTime, booked.endTime, 'Appointment end should come from the slot');
        System.assertEquals(true, String.isNotBlank(booked.appointmentName), 'NameFormatter should set Appointment Name');

        Appointment__c saved = [
            SELECT Patient__c, Practitioner__c, Slot__c, Start__c, End__c, Status__c, Appointment_Type__c, Reason__c, Location_Name__c
            FROM Appointment__c
            WHERE Id = :booked.appointmentId
        ];
        System.assertEquals(firstPatient.Id, saved.Patient__c, 'Patient should be stored');
        System.assertEquals(practitioner.Id, saved.Practitioner__c, 'Practitioner should come from the slot schedule');
        System.assertEquals(slot.Id, saved.Slot__c, 'Slot lookup should be stored');
        System.assertEquals(startTime, saved.Start__c, 'Start should copy from the locked slot');
        System.assertEquals(endTime, saved.End__c, 'End should copy from the locked slot');
        System.assertEquals('Booked', saved.Status__c, 'Status should be Booked');
        System.assertEquals(TYPE_CHECKUP, saved.Appointment_Type__c, 'Appointment type should be stored');
        System.assertEquals('Annual visit', saved.Reason__c, 'Reason should be stored');
        System.assertEquals('Clinic A', saved.Location_Name__c, 'Location should copy from the schedule');

        Slot__c afterFirst = [SELECT Status__c FROM Slot__c WHERE Id = :slot.Id];
        System.assertEquals('Busy', afterFirst.Status__c, 'Successful book should set the slot to Busy');
        System.assertEquals(1, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id], 'Only the first booking should persist');
        System.assertEquals(true, secondRejected, 'A second booking against the same slot must be rejected');
        System.assert(
            rejectMessage != null && rejectMessage.contains('Busy'),
            'Reject message should say the slot is Busy. Actual: ' + rejectMessage
        );
        AppointmentBookingController.SlotListView remaining = AppointmentBookingController.getFreeSlots(
            practitioner.Id,
            'Clinic A',
            SLOT_DAY,
            SLOT_DAY
        );
        System.assertEquals(0, remaining.slots.size(), 'A booked slot must no longer appear as Free');
    }

    @IsTest
    static void bookRejectsSlotAlreadyBusy() {
        Patient__c patient = insertPatient('MRN-BOOK-BUSY');
        Practitioner__c practitioner = insertPractitioner('Ben', 'Ng');
        Slot__c slot = insertSlot(
            insertSchedule(practitioner.Id, 'Clinic B').Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(10, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(10, 20, 0, 0)),
            'Busy'
        );

        Test.startTest();
        Boolean rejected = false;
        try {
            AppointmentBookingController.bookAppointment(patient.Id, slot.Id, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            rejected = true;
        }
        Test.stopTest();

        System.assertEquals(true, rejected, 'Booking a Busy slot should be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Appointment__c WHERE Slot__c = :slot.Id], 'No appointment should be created');
        System.assertEquals('Busy', [SELECT Status__c FROM Slot__c WHERE Id = :slot.Id].Status__c, 'Slot should remain Busy');
    }

    @IsTest
    static void getFreeSlotsAndLocationsFilterAvailability() {
        Practitioner__c practitioner = insertPractitioner('Cara', 'Singh');
        Practitioner__c other = insertPractitioner('Drew', 'Patel');
        Schedule__c clinicA = insertSchedule(practitioner.Id, 'Clinic A');
        Schedule__c clinicB = insertSchedule(practitioner.Id, 'Clinic B');
        Schedule__c otherSchedule = insertSchedule(other.Id, 'Clinic A');
        Datetime freeStart = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        insert new List<Slot__c>{
            new Slot__c(
                Schedule__c = clinicA.Id,
                Start__c = freeStart,
                End__c = freeStart.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = clinicA.Id,
                Start__c = freeStart.addMinutes(20),
                End__c = freeStart.addMinutes(40),
                Status__c = 'Busy'
            ),
            new Slot__c(
                Schedule__c = clinicA.Id,
                Start__c = freeStart.addMinutes(40),
                End__c = freeStart.addMinutes(60),
                Status__c = 'Blocked'
            ),
            new Slot__c(
                Schedule__c = clinicB.Id,
                Start__c = freeStart.addHours(1),
                End__c = freeStart.addHours(1).addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = otherSchedule.Id,
                Start__c = freeStart,
                End__c = freeStart.addMinutes(20),
                Status__c = 'Free'
            )
        };

        Test.startTest();
        List<String> allLocations = AppointmentBookingController.getLocations(null);
        List<String> locations = AppointmentBookingController.getLocations(practitioner.Id);
        AppointmentBookingController.SlotListView allFree = AppointmentBookingController.getFreeSlots(
            practitioner.Id,
            null,
            SLOT_DAY,
            SLOT_DAY
        );
        AppointmentBookingController.SlotListView clinicAOnly = AppointmentBookingController.getFreeSlots(
            practitioner.Id,
            'Clinic A',
            SLOT_DAY,
            SLOT_DAY
        );
        Test.stopTest();

        System.assertEquals(new List<String>{ 'Clinic A', 'Clinic B' }, allLocations, 'Locations without a provider should include every active schedule location');
        System.assertEquals(new List<String>{ 'Clinic A', 'Clinic B' }, locations, 'Active schedule locations should be distinct and sorted');
        System.assertEquals(2, allFree.slots.size(), 'Only Free slots for the chosen provider should be returned');
        System.assertEquals(false, allFree.hasMore, 'Two slots should not exceed the list limit');
        System.assertEquals(1, clinicAOnly.slots.size(), 'Location filter should return only Clinic A free slots');
        System.assertEquals('Clinic A', clinicAOnly.slots[0].locationName, 'Slot view should include the schedule location');
        System.assertEquals(practitioner.Id, clinicAOnly.slots[0].practitionerId, 'Slot view should include the provider');
        System.assertEquals(freeStart, clinicAOnly.slots[0].startTime, 'Slot view start should match the Free slot');
    }

    @IsTest
    static void getAvailableProvidersReturnsProvidersWithFreeSlotsOnDates() {
        Practitioner__c ada = insertPractitioner('Ada', 'Lopez');
        ada.Specialty__c = 'Primary Care';
        update ada;
        Practitioner__c ben = insertPractitioner('Ben', 'Ng');
        ben.Specialty__c = 'Cardiology';
        update ben;
        Practitioner__c inactive = insertPractitioner('Cara', 'Singh');
        inactive.Active__c = false;
        update inactive;
        Schedule__c adaClinicA = insertSchedule(ada.Id, 'Clinic A');
        Schedule__c adaClinicB = insertSchedule(ada.Id, 'Clinic B');
        Schedule__c benClinicA = insertSchedule(ben.Id, 'Clinic A');
        Schedule__c inactiveSchedule = insertSchedule(inactive.Id, 'Clinic A');
        Datetime inRange = DateTime.newInstance(SLOT_DAY, Time.newInstance(9, 0, 0, 0));
        Datetime laterSameDay = DateTime.newInstance(SLOT_DAY, Time.newInstance(14, 0, 0, 0));
        Datetime outsideRange = DateTime.newInstance(SLOT_DAY.addDays(3), Time.newInstance(9, 0, 0, 0));
        insert new List<Slot__c>{
            new Slot__c(
                Schedule__c = adaClinicA.Id,
                Start__c = inRange,
                End__c = inRange.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = adaClinicB.Id,
                Start__c = laterSameDay,
                End__c = laterSameDay.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = adaClinicA.Id,
                Start__c = inRange.addHours(1),
                End__c = inRange.addHours(1).addMinutes(20),
                Status__c = 'Busy'
            ),
            new Slot__c(
                Schedule__c = benClinicA.Id,
                Start__c = inRange,
                End__c = inRange.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = benClinicA.Id,
                Start__c = outsideRange,
                End__c = outsideRange.addMinutes(20),
                Status__c = 'Free'
            ),
            new Slot__c(
                Schedule__c = inactiveSchedule.Id,
                Start__c = inRange,
                End__c = inRange.addMinutes(20),
                Status__c = 'Free'
            )
        };

        Test.startTest();
        List<AppointmentBookingController.ProviderAvailabilityView> allProviders = AppointmentBookingController.getAvailableProviders(
            SLOT_DAY,
            SLOT_DAY,
            null
        );
        List<AppointmentBookingController.ProviderAvailabilityView> clinicBOnly = AppointmentBookingController.getAvailableProviders(
            SLOT_DAY,
            SLOT_DAY,
            'Clinic B'
        );
        List<AppointmentBookingController.ProviderAvailabilityView> emptyDay = AppointmentBookingController.getAvailableProviders(
            SLOT_DAY.addDays(1),
            SLOT_DAY.addDays(1),
            null
        );
        Boolean missingDates = false;
        try {
            AppointmentBookingController.getAvailableProviders(null, SLOT_DAY, null);
        } catch (AuraHandledException e) {
            missingDates = true;
        }
        Boolean invertedRange = false;
        try {
            AppointmentBookingController.getAvailableProviders(SLOT_DAY, SLOT_DAY.addDays(-1), null);
        } catch (AuraHandledException e) {
            invertedRange = true;
        }
        Test.stopTest();

        System.assertEquals(2, allProviders.size(), 'Only active providers with Free slots on the chosen dates should be returned');
        AppointmentBookingController.ProviderAvailabilityView adaView = findProvider(allProviders, ada.Id);
        AppointmentBookingController.ProviderAvailabilityView benView = findProvider(allProviders, ben.Id);
        System.assertNotEquals(null, adaView, 'Ada should appear because she has Free slots on the chosen date');
        System.assertNotEquals(null, benView, 'Ben should appear because he has a Free slot on the chosen date');
        System.assertEquals(null, findProvider(allProviders, inactive.Id), 'Inactive providers must not appear even if they have Free slots');
        System.assertEquals('Primary Care', adaView.specialty, 'Specialty should come from the practitioner');
        System.assertEquals('Clinic A, Clinic B', adaView.locationNames, 'Locations with Free slots should be merged and sorted');
        System.assertEquals(2, adaView.freeSlotCount, 'Busy slots and other providers must not count toward Ada');
        System.assertEquals(inRange, adaView.earliestStart, 'Earliest Free slot should be returned');
        System.assertEquals(laterSameDay, adaView.latestStart, 'Latest Free slot should be returned');
        System.assertEquals(1, benView.freeSlotCount, 'Ben should count only the in-range Free slot');
        System.assertEquals(1, clinicBOnly.size(), 'Location filter should hide providers without Free slots there');
        System.assertEquals(ada.Id, clinicBOnly[0].practitionerId, 'Clinic B filter should return Ada only');
        System.assertEquals('Clinic B', clinicBOnly[0].locationNames, 'Filtered result should list the selected location');
        System.assertEquals(0, emptyDay.size(), 'A day with no Free slots should return no providers');
        System.assertEquals(true, missingDates, 'getAvailableProviders without dates should throw');
        System.assertEquals(true, invertedRange, 'Inverted provider date range should throw');
    }

    @IsTest
    static void bookAndLookupValidationErrors() {
        Patient__c patient = insertPatient('MRN-BOOK-VAL');
        Practitioner__c practitioner = insertPractitioner('Eli', 'Park');
        Slot__c freeSlot = insertSlot(
            insertSchedule(practitioner.Id, 'Clinic C').Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(11, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(11, 20, 0, 0)),
            'Free'
        );
        Slot__c blockedSlot = insertSlot(
            insertSchedule(practitioner.Id, 'Clinic C').Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(12, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(12, 20, 0, 0)),
            'Blocked'
        );
        Slot__c orphanSlot = insertSlot(
            insertSchedule(null, null).Id,
            DateTime.newInstance(SLOT_DAY, Time.newInstance(13, 0, 0, 0)),
            DateTime.newInstance(SLOT_DAY, Time.newInstance(13, 20, 0, 0)),
            'Free'
        );
        Id missingSlotId = blockedSlot.Id;
        delete blockedSlot;

        Test.startTest();
        Boolean missingPatient = threwOnBook(null, freeSlot.Id, TYPE_CHECKUP);
        Boolean missingSlot = threwOnBook(patient.Id, null, TYPE_CHECKUP);
        Boolean badType = threwOnBook(patient.Id, freeSlot.Id, 'Not-a-type');
        Boolean blankType = threwOnBook(patient.Id, freeSlot.Id, '  ');
        Boolean unknownPatient = false;
        try {
            AppointmentBookingController.bookAppointment(UserInfo.getUserId(), freeSlot.Id, TYPE_CHECKUP, null);
        } catch (AuraHandledException e) {
            unknownPatient = true;
        }
        Boolean unknownSlot = threwOnBook(patient.Id, missingSlotId, TYPE_CHECKUP);
        Boolean noProvider = threwOnBook(patient.Id, orphanSlot.Id, TYPE_CHECKUP);
        Boolean slotsBlank = false;
        try {
            AppointmentBookingController.getFreeSlots(null, null, SLOT_DAY, SLOT_DAY);
        } catch (AuraHandledException e) {
            slotsBlank = true;
        }
        Boolean slotsDates = false;
        try {
            AppointmentBookingController.getFreeSlots(practitioner.Id, null, null, SLOT_DAY);
        } catch (AuraHandledException e) {
            slotsDates = true;
        }
        Boolean slotsRange = false;
        try {
            AppointmentBookingController.getFreeSlots(practitioner.Id, null, SLOT_DAY, SLOT_DAY.addDays(-1));
        } catch (AuraHandledException e) {
            slotsRange = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Book without a patient should throw');
        System.assertEquals(true, missingSlot, 'Book without a slot should throw');
        System.assertEquals(true, badType, 'Invalid appointment type should throw');
        System.assertEquals(true, blankType, 'Blank appointment type should throw');
        System.assertEquals(true, unknownPatient, 'Unknown patient Id should throw');
        System.assertEquals(true, unknownSlot, 'Deleted slot should throw');
        System.assertEquals(true, noProvider, 'Slot without a provider should throw');
        System.assertEquals(true, slotsBlank, 'getFreeSlots without a provider should throw');
        System.assertEquals(true, slotsDates, 'getFreeSlots without dates should throw');
        System.assertEquals(true, slotsRange, 'Inverted slot date range should throw');
        System.assertEquals(0, [SELECT COUNT() FROM Appointment__c], 'Validation failures must not insert appointments');
        System.assertEquals('Free', [SELECT Status__c FROM Slot__c WHERE Id = :freeSlot.Id].Status__c, 'Failed books must leave the Free slot Free');
    }

    private static AppointmentBookingController.ProviderAvailabilityView findProvider(
        List<AppointmentBookingController.ProviderAvailabilityView> providers,
        Id practitionerId
    ) {
        for (AppointmentBookingController.ProviderAvailabilityView view : providers) {
            if (view.practitionerId == practitionerId) {
                return view;
            }
        }
        return null;
    }

    private static Boolean threwOnBook(Id patientId, Id slotId, String appointmentType) {
        try {
            AppointmentBookingController.bookAppointment(patientId, slotId, appointmentType, null);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Booking');
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
}
