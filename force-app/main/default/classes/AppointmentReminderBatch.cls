global with sharing class AppointmentReminderBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    public static String lastSummary;

    private Integer sentCount = 0;
    private Integer skippedCount = 0;
    private Integer failedCount = 0;

    global Database.QueryLocator start(Database.BatchableContext context) {
        Appointment_Comm_Config__mdt config = AppointmentCommunicationService.getConfig();
        Decimal hours = config.Reminder_Hours_Before__c == null ? 24 : config.Reminder_Hours_Before__c;
        Datetime windowStart = Datetime.now();
        Datetime windowEnd = windowStart.addHours(Integer.valueOf(hours));
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Appointment__c
                WHERE
                    Status__c = :AppointmentCommunicationService.APPT_BOOKED
                    AND Reminder_Sent_At__c = NULL
                    AND Start__c > :windowStart
                    AND Start__c <= :windowEnd
            ]
        );
    }

    global void execute(Database.BatchableContext context, List<SObject> scope) {
        List<Id> appointmentIds = new List<Id>();
        for (SObject row : scope) {
            appointmentIds.add(row.Id);
        }
        AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendForAppointments(
            appointmentIds,
            AppointmentCommunicationService.TYPE_REMINDER,
            AppointmentCommunicationService.TRIGGER_AUTOMATED,
            null,
            true
        );
        sentCount += result.sentCount == null ? 0 : result.sentCount;
        skippedCount += result.skippedCount == null ? 0 : result.skippedCount;
        failedCount += result.failedCount == null ? 0 : result.failedCount;
    }

    global void finish(Database.BatchableContext context) {
        lastSummary =
            'Reminders sent=' +
            sentCount +
            ', skipped=' +
            skippedCount +
            ', failed=' +
            failedCount;
    }
}
