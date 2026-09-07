@IsTest
private class AppointmentCommunicationHandlerTest {
    @IsTest
    static void bookQueuesAutomatedConfirmation() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-HND-1',
            First_Name__c = 'Book',
            Last_Name__c = 'Confirm',
            Email__c = 'book@example.com'
        );
        insert patient;
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = 'A', Last_Name__c = 'B');
        insert practitioner;

        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.testConfigOverride = enabledConfig();

        Test.startTest();
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addDays(1),
            End__c = Datetime.now().addDays(1).addMinutes(20),
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup',
            Location_Name__c = 'Clinic'
        );
        insert appointment;
        Test.stopTest();

        Appointment__c stamped = [
            SELECT Confirmation_Sent_At__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertNotEquals(
            null,
            stamped.Confirmation_Sent_At__c,
            'Automated confirmation should stamp Confirmation_Sent_At__c'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Appointment_Communication__c
                WHERE
                    Appointment__c = :appointment.Id
                    AND Type__c = 'Confirmation'
                    AND Triggered_By__c = 'Automated'
                    AND Status__c = 'Sent'
            ],
            'Automated confirmation email log expected'
        );
    }

    @IsTest
    static void rescheduleClearsReminderAndResendsConfirmation() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-HND-2',
            First_Name__c = 'Re',
            Last_Name__c = 'Schedule',
            Email__c = 'reschedule@example.com'
        );
        insert patient;
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = 'C', Last_Name__c = 'D');
        insert practitioner;

        AppointmentCommunicationHandler.bypass = true;
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addDays(2),
            End__c = Datetime.now().addDays(2).addMinutes(20),
            Status__c = 'Booked',
            Confirmation_Sent_At__c = Datetime.now().addDays(-1),
            Reminder_Sent_At__c = Datetime.now().addDays(-1),
            Appointment_Type__c = 'Follow-up',
            Location_Name__c = 'Clinic'
        );
        insert appointment;
        AppointmentCommunicationHandler.bypass = false;

        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.testConfigOverride = enabledConfig();

        Test.startTest();
        appointment.Start__c = appointment.Start__c.addDays(1);
        appointment.End__c = appointment.End__c.addDays(1);
        update appointment;
        Test.stopTest();

        Appointment__c refreshed = [
            SELECT Confirmation_Sent_At__c, Reminder_Sent_At__c, Start__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertEquals(null, refreshed.Reminder_Sent_At__c, 'Reschedule should clear Reminder_Sent_At__c');
        System.assertNotEquals(
            null,
            refreshed.Confirmation_Sent_At__c,
            'Reschedule should re-send confirmation and stamp again'
        );
        System.assert(
            [
                SELECT COUNT()
                FROM Appointment_Communication__c
                WHERE Appointment__c = :appointment.Id AND Type__c = 'Confirmation' AND Triggered_By__c = 'Automated'
            ] >= 1,
            'Reschedule should create a confirmation communication'
        );
    }

    private static Appointment_Comm_Config__mdt enabledConfig() {
        Appointment_Comm_Config__mdt config = new Appointment_Comm_Config__mdt();
        config.Email_Enabled__c = true;
        config.SMS_Enabled__c = false;
        config.Auto_Send_Confirmation__c = true;
        config.Auto_Send_Reminder__c = true;
        config.Reminder_Hours_Before__c = 24;
        return config;
    }
}
