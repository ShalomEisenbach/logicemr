public with sharing class AppointmentCommunicationController {
    @AuraEnabled(cacheable=true)
    public static AppointmentCommunicationService.ChannelAvailability getChannelAvailability(Id appointmentId) {
        try {
            return AppointmentCommunicationService.getChannelAvailability(appointmentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static AppointmentCommunicationService.SendResult sendConfirmation(Id appointmentId, List<String> channels) {
        try {
            return AppointmentCommunicationService.sendConfirmation(appointmentId, false, channels);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static AppointmentCommunicationService.SendResult sendReminder(Id appointmentId, List<String> channels) {
        try {
            return AppointmentCommunicationService.sendReminder(appointmentId, false, channels);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static AppointmentCommunicationService.PrintPayload getPrintPayload(Id appointmentId) {
        try {
            return AppointmentCommunicationService.getPrintPayload(appointmentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static AppointmentCommunicationService.SendResult logPrint(Id appointmentId) {
        try {
            return AppointmentCommunicationService.logPrint(appointmentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
