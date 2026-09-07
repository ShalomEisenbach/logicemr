public with sharing class AppointmentCommunicationHandler {
    @TestVisible
    public static Boolean bypass = false;

    public static void beforeUpdate(List<Appointment__c> newList, Map<Id, Appointment__c> oldMap) {
        if (bypass == true || newList == null || oldMap == null) {
            return;
        }
        for (Appointment__c appointment : newList) {
            Appointment__c prior = oldMap.get(appointment.Id);
            if (prior == null) {
                continue;
            }
            if (appointment.Start__c != prior.Start__c) {
                appointment.Reminder_Sent_At__c = null;
                appointment.Confirmation_Sent_At__c = null;
            }
        }
    }

    public static void afterInsert(List<Appointment__c> newList) {
        if (bypass == true || newList == null || newList.isEmpty()) {
            return;
        }
        Appointment_Comm_Config__mdt config = AppointmentCommunicationService.getConfig();
        if (config.Auto_Send_Confirmation__c != true) {
            return;
        }
        List<Id> toConfirm = new List<Id>();
        for (Appointment__c appointment : newList) {
            if (appointment.Status__c == AppointmentCommunicationService.APPT_BOOKED) {
                toConfirm.add(appointment.Id);
            }
        }
        enqueueConfirmations(toConfirm);
    }

    public static void afterUpdate(List<Appointment__c> newList, Map<Id, Appointment__c> oldMap) {
        if (bypass == true || newList == null || oldMap == null || newList.isEmpty()) {
            return;
        }
        Appointment_Comm_Config__mdt config = AppointmentCommunicationService.getConfig();
        if (config.Auto_Send_Confirmation__c != true) {
            return;
        }
        List<Id> toConfirm = new List<Id>();
        for (Appointment__c appointment : newList) {
            Appointment__c prior = oldMap.get(appointment.Id);
            if (prior == null) {
                continue;
            }
            if (appointment.Status__c != AppointmentCommunicationService.APPT_BOOKED) {
                continue;
            }
            Boolean becameBooked = prior.Status__c != AppointmentCommunicationService.APPT_BOOKED;
            Boolean startChanged = appointment.Start__c != prior.Start__c;
            if (becameBooked || startChanged) {
                toConfirm.add(appointment.Id);
            }
        }
        enqueueConfirmations(toConfirm);
    }

    private static void enqueueConfirmations(List<Id> appointmentIds) {
        if (appointmentIds == null || appointmentIds.isEmpty()) {
            return;
        }
        if (System.isQueueable() || System.isFuture() || System.isBatch() || System.isScheduled()) {
            AppointmentCommunicationService.sendForAppointments(
                appointmentIds,
                AppointmentCommunicationService.TYPE_CONFIRMATION,
                AppointmentCommunicationService.TRIGGER_AUTOMATED,
                null,
                true
            );
            return;
        }
        System.enqueueJob(new AppointmentConfirmationQueueable(appointmentIds));
    }
}
