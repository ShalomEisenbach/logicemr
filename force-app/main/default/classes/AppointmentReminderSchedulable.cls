global with sharing class AppointmentReminderSchedulable implements Schedulable {
    global void execute(SchedulableContext context) {
        Appointment_Comm_Config__mdt config = AppointmentCommunicationService.getConfig();
        if (config.Auto_Send_Reminder__c != true) {
            return;
        }
        Database.executeBatch(new AppointmentReminderBatch(), 50);
    }
}
