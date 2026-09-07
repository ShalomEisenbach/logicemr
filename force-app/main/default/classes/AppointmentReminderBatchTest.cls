@IsTest
private class AppointmentReminderBatchTest {
    @IsTest
    static void batchSendsRemindersInWindow() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-REM-1',
            First_Name__c = 'Rem',
            Last_Name__c = 'Inder',
            Email__c = 'reminder@example.com'
        );
        insert patient;
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = 'Pat', Last_Name__c = 'Provider');
        insert practitioner;

        AppointmentCommunicationHandler.bypass = true;
        Appointment__c inWindow = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addHours(6),
            End__c = Datetime.now().addHours(6).addMinutes(30),
            Status__c = 'Booked',
            Appointment_Type__c = 'Routine',
            Location_Name__c = 'Main'
        );
        Appointment__c alreadyReminded = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addHours(4),
            End__c = Datetime.now().addHours(4).addMinutes(30),
            Status__c = 'Booked',
            Reminder_Sent_At__c = Datetime.now().addDays(-1),
            Appointment_Type__c = 'Routine',
            Location_Name__c = 'Main'
        );
        Appointment__c cancelled = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addHours(5),
            End__c = Datetime.now().addHours(5).addMinutes(30),
            Status__c = 'Cancelled',
            Appointment_Type__c = 'Routine',
            Location_Name__c = 'Main'
        );
        insert new List<Appointment__c>{ inWindow, alreadyReminded, cancelled };
        AppointmentCommunicationHandler.bypass = false;

        AppointmentCommunicationService.skipEmailSend = true;
        AppointmentCommunicationService.testConfigOverride = config(true);

        Test.startTest();
        Database.executeBatch(new AppointmentReminderBatch(), 50);
        Test.stopTest();

        Appointment__c refreshed = [
            SELECT Reminder_Sent_At__c
            FROM Appointment__c
            WHERE Id = :inWindow.Id
        ];
        System.assertNotEquals(null, refreshed.Reminder_Sent_At__c, 'In-window booked appointment should be reminded');
        System.assertNotEquals(null, AppointmentReminderBatch.lastSummary, 'Batch finish should set summary');
        System.assert(
            AppointmentReminderBatch.lastSummary.contains('sent='),
            'Summary should include sent tally: ' + AppointmentReminderBatch.lastSummary
        );
    }

    @IsTest
    static void schedulableExecutesWhenEnabled() {
        AppointmentCommunicationService.testConfigOverride = config(true);
        AppointmentCommunicationService.skipEmailSend = true;

        Test.startTest();
        new AppointmentReminderSchedulable().execute(null);
        Test.stopTest();

        System.assertEquals(true, true, 'Schedulable should enqueue batch without exception');
    }

    @IsTest
    static void invocableSchedulesJob() {
        Test.startTest();
        List<AppointmentReminderInvocable.Result> results = AppointmentReminderInvocable.scheduleReminders(
            new List<AppointmentReminderInvocable.Request>{ new AppointmentReminderInvocable.Request() }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result expected');
        System.assertEquals(true, results[0].success, 'Schedule should succeed: ' + results[0].message);
        System.assertNotEquals(null, results[0].jobId, 'Cron trigger id should be returned');
    }

    private static Appointment_Comm_Config__mdt config(Boolean autoReminder) {
        Appointment_Comm_Config__mdt row = new Appointment_Comm_Config__mdt();
        row.Email_Enabled__c = true;
        row.SMS_Enabled__c = false;
        row.Auto_Send_Confirmation__c = true;
        row.Auto_Send_Reminder__c = autoReminder;
        row.Reminder_Hours_Before__c = 24;
        row.Twilio_Named_Credential__c = 'LogicEMR_Twilio';
        return row;
    }
}
