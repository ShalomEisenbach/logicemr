@IsTest
private class AppointmentCommunicationServiceTest {
    @IsTest
    static void sendConfirmationEmailsAndSkipsSmsWithoutOptIn() {
        Patient__c patient = insertPatient('MRN-COMM-1', 'ada@example.com', '555-010-0001', false);
        Appointment__c appointment = insertBookedAppointment(patient.Id, Datetime.now().addDays(1));

        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.skipSmsEnqueue = true;
        Appointment_Comm_Config__mdt config = baseConfig(true, true);
        AppointmentCommunicationService.testConfigOverride = config;

        Test.startTest();
        AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendConfirmation(
            appointment.Id,
            false,
            new List<String>{ 'Email', 'SMS' }
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Email-only send should succeed: ' + result.message);
        System.assertEquals(1, result.sentCount, 'One email should be counted as sent');
        System.assert(
            result.skippedCount >= 1,
            'SMS without opt-in should be skipped: ' + result.message
        );

        Appointment__c stamped = [
            SELECT Confirmation_Sent_At__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertNotEquals(null, stamped.Confirmation_Sent_At__c, 'Confirmation timestamp should be set');

        List<Appointment_Communication__c> logs = [
            SELECT Channel__c, Status__c, Type__c, Triggered_By__c, Recipient__c
            FROM Appointment_Communication__c
            WHERE Appointment__c = :appointment.Id
            ORDER BY Channel__c
        ];
        System.assert(logs.size() >= 1, 'At least one communication log should exist');
        Boolean foundEmail = false;
        Boolean foundSmsSkip = false;
        for (Appointment_Communication__c row : logs) {
            if (row.Channel__c == 'Email' && row.Status__c == 'Sent') {
                foundEmail = true;
                System.assertEquals('ada@example.com', row.Recipient__c, 'Email recipient should match');
                System.assertEquals('Manual', row.Triggered_By__c, 'Manual send should be tagged');
            }
            if (row.Channel__c == 'SMS' && row.Status__c == 'Skipped') {
                foundSmsSkip = true;
            }
        }
        System.assertEquals(true, foundEmail, 'Email Sent log expected');
        System.assertEquals(true, foundSmsSkip, 'SMS Skipped log expected without opt-in');
    }

    @IsTest
    static void sendSkipsWhenNoEmail() {
        Patient__c patient = insertPatient('MRN-COMM-2', null, null, false);
        Appointment__c appointment = insertBookedAppointment(patient.Id, Datetime.now().addDays(2));
        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.testConfigOverride = baseConfig(true, false);

        Test.startTest();
        AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendConfirmation(
            appointment.Id,
            true,
            null
        );
        Test.stopTest();

        System.assertEquals(0, result.sentCount, 'No channels should send');
        System.assert(result.skippedCount >= 1, 'Should record a skip');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Appointment__c
                WHERE Id = :appointment.Id AND Confirmation_Sent_At__c != NULL
            ],
            'Timestamp should not set when nothing was sent'
        );
    }

    @IsTest
    static void getChannelAvailabilityAndPrintPayload() {
        Patient__c patient = insertPatient('MRN-COMM-3', 'print@example.com', '555-010-0003', true);
        Appointment__c appointment = insertBookedAppointment(patient.Id, Datetime.now().addDays(3));
        AppointmentCommunicationService.testConfigOverride = baseConfig(true, false);

        AppointmentCommunicationService.ChannelAvailability availability =
            AppointmentCommunicationService.getChannelAvailability(appointment.Id);
        System.assertEquals(true, availability.emailAvailable, 'Email should be available');
        System.assertEquals(false, availability.smsAvailable, 'SMS disabled in config');
        System.assertEquals('print@example.com', availability.emailRecipient, 'Recipient email');

        AppointmentCommunicationService.PrintPayload payload = AppointmentCommunicationService.getPrintPayload(
            appointment.Id
        );
        System.assertEquals(appointment.Id, payload.appointmentId, 'Payload appointment id');
        System.assertEquals(patient.Id, payload.patientId, 'Payload patient id');
        System.assertEquals('Booked', payload.status, 'Payload status');

        AppointmentCommunicationService.SendResult printResult = AppointmentCommunicationService.logPrint(
            appointment.Id
        );
        System.assertEquals(true, printResult.success, 'Print log should succeed');
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Appointment_Communication__c
                WHERE Appointment__c = :appointment.Id AND Channel__c = 'Print' AND Status__c = 'Sent'
            ],
            'Print channel log expected'
        );
    }

    @IsTest
    static void enqueueSmsJobWithMockCallout() {
        Patient__c patient = insertPatient('MRN-COMM-4', 'sms@example.com', '5550100004', true);
        Appointment__c appointment = insertBookedAppointment(patient.Id, Datetime.now().addDays(4));
        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.skipSmsEnqueue = false;
        AppointmentCommunicationService.testConfigOverride = baseConfig(true, true);

        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());
        Test.startTest();
        AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendReminder(
            appointment.Id,
            false,
            new List<String>{ 'SMS' }
        );
        Test.stopTest();

        System.assert(result.sentCount >= 1, 'SMS send should count: ' + result.message);
        Appointment__c stamped = [
            SELECT Reminder_Sent_At__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertNotEquals(null, stamped.Reminder_Sent_At__c, 'Reminder timestamp should be set');
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Appointment_Communication__c
                WHERE Appointment__c = :appointment.Id AND Channel__c = 'SMS' AND Status__c = 'Sent'
            ],
            'SMS Sent log expected after successful Twilio mock'
        );
    }

    @IsTest
    static void controllerDelegates() {
        Patient__c patient = insertPatient('MRN-COMM-5', 'ctrl@example.com', '555-010-0005', false);
        Appointment__c appointment = insertBookedAppointment(patient.Id, Datetime.now().addDays(5));
        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.testConfigOverride = baseConfig(true, false);

        Test.startTest();
        AppointmentCommunicationService.ChannelAvailability availability =
            AppointmentCommunicationController.getChannelAvailability(appointment.Id);
        AppointmentCommunicationService.SendResult sent = AppointmentCommunicationController.sendConfirmation(
            appointment.Id,
            new List<String>{ 'Email' }
        );
        AppointmentCommunicationService.PrintPayload payload = AppointmentCommunicationController.getPrintPayload(
            appointment.Id
        );
        AppointmentCommunicationService.SendResult printed = AppointmentCommunicationController.logPrint(
            appointment.Id
        );
        Test.stopTest();

        System.assertEquals(true, availability.emailAvailable, 'Controller availability');
        System.assertEquals(true, sent.success, 'Controller send confirmation');
        System.assertEquals(appointment.Id, payload.appointmentId, 'Controller print payload');
        System.assertEquals(true, printed.success, 'Controller print log');
    }

    private static Appointment_Comm_Config__mdt baseConfig(Boolean emailEnabled, Boolean smsEnabled) {
        Appointment_Comm_Config__mdt config = new Appointment_Comm_Config__mdt();
        config.Email_Enabled__c = emailEnabled;
        config.SMS_Enabled__c = smsEnabled;
        config.Auto_Send_Confirmation__c = true;
        config.Auto_Send_Reminder__c = true;
        config.Reminder_Hours_Before__c = 24;
        config.Twilio_Named_Credential__c = 'LogicEMR_Twilio';
        config.Twilio_Account_Sid__c = 'ACtestsid';
        config.Twilio_From_Number__c = '+15551234567';
        return config;
    }

    private static Patient__c insertPatient(String mrn, String email, String phone, Boolean smsOptIn) {
        Patient__c patient = new Patient__c(
            MRN__c = mrn,
            First_Name__c = 'Ada',
            Last_Name__c = 'Comm',
            Email__c = email,
            Phone__c = phone,
            SMS_Opt_In__c = smsOptIn
        );
        insert patient;
        return patient;
    }

    private static Appointment__c insertBookedAppointment(Id patientId, Datetime startTime) {
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = 'Doc', Last_Name__c = 'Who');
        insert practitioner;
        AppointmentCommunicationHandler.bypass = true;
        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Practitioner__c = practitioner.Id,
            Start__c = startTime,
            End__c = startTime.addMinutes(30),
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup',
            Location_Name__c = 'Clinic A',
            Reason__c = 'Follow-up'
        );
        insert appointment;
        AppointmentCommunicationHandler.bypass = false;
        return appointment;
    }

    private class TwilioSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(201);
            response.setBody('{"sid":"SMxxxxxxxx","status":"queued"}');
            return response;
        }
    }
}
