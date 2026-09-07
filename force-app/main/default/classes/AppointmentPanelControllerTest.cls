@IsTest
private class AppointmentPanelControllerTest {
    @IsTest
    static void getAppointmentsReturnsNewestFirstWithExpectedShape() {
        Patient__c patient = insertPatient('MRN-APPT-1');
        Patient__c otherPatient = insertPatient('MRN-APPT-2');
        Practitioner__c attending = insertPractitioner('Jordan', 'Lee');

        Datetime olderStart = Datetime.newInstance(2026, 8, 15, 9, 0, 0);
        Datetime newerStart = Datetime.newInstance(2026, 9, 2, 14, 30, 0);

        Appointment__c older = insertAppointment(
            patient.Id,
            attending.Id,
            olderStart,
            'Follow-up',
            'Booked',
            'Hypertension check'
        );
        Appointment__c newer = insertAppointment(
            patient.Id,
            attending.Id,
            newerStart,
            'Checkup',
            'Arrived',
            'Annual physical'
        );
        insertAppointment(otherPatient.Id, attending.Id, newerStart, 'Routine', 'Booked', 'Other patient');

        Test.startTest();
        List<Appointment__c> results = AppointmentPanelController.getAppointments(patient.Id);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return only this patient\'s appointments');
        System.assertEquals(newer.Id, results[0].Id, 'Newest Start__c should be first');
        System.assertEquals(older.Id, results[1].Id, 'Older appointment should be second');
        System.assertEquals('Arrived', results[0].Status__c, 'Status__c should be populated');
        System.assertEquals('Checkup', results[0].Appointment_Type__c, 'Appointment_Type__c should be populated');
        System.assertEquals(newerStart, results[0].Start__c, 'Start__c should be populated');
        System.assertEquals(attending.Id, results[0].Practitioner__c, 'Practitioner lookup should be populated');
        System.assertEquals(
            'Jordan',
            results[0].Practitioner__r.First_Name__c,
            'Practitioner first name should be queried'
        );
        System.assertEquals(
            'Lee',
            results[0].Practitioner__r.Last_Name__c,
            'Practitioner last name should be queried'
        );
        System.assertEquals('Annual physical', results[0].Reason__c, 'Reason should be queried');
    }

    @IsTest
    static void getAppointmentsReturnsEmptyForBlankOrUnrelatedPatient() {
        Patient__c patient = insertPatient('MRN-APPT-3');

        Test.startTest();
        List<Appointment__c> blankId = AppointmentPanelController.getAppointments(null);
        List<Appointment__c> none = AppointmentPanelController.getAppointments(patient.Id);
        Test.stopTest();

        System.assertEquals(0, blankId.size(), 'Null patient Id should return no rows');
        System.assertEquals(0, none.size(), 'A patient with no appointments should return no rows');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Chart');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(String firstName, String lastName) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = firstName,
            Last_Name__c = lastName
        );
        insert practitioner;
        return practitioner;
    }

    private static Appointment__c insertAppointment(
        Id patientId,
        Id practitionerId,
        Datetime startTime,
        String appointmentType,
        String status,
        String reason
    ) {
        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Practitioner__c = practitionerId,
            Start__c = startTime,
            End__c = startTime.addMinutes(20),
            Appointment_Type__c = appointmentType,
            Status__c = status,
            Reason__c = reason,
            Location_Name__c = 'Primary Care Clinic A'
        );
        insert appointment;
        return appointment;
    }
}
